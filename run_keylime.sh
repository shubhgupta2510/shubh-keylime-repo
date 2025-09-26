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
docker stop keylime-agent keylime-verifier keylime-registrar keylime-mitm && docker rm keylime-agent keylime-verifier keylime-registrar keylime-mitm
echo "Existing containers stopped and removed.\n\n"

# STEP 4: Start the Keylime services
echo "Starting Keylime services using Docker Compose..."
docker compose up -d registrar verifier agent mitm
echo "\n\n"

# STEP 5: View the logs for the Keylime agent - Should get a RegistrarClientBuilder Error
echo "Viewing logs for the Keylime agent..."
sleep 30
docker logs keylime-agent
echo "\n\n"

# STEP 6: Delete agent from registrar
echo "Deleting agent from registrar..."
docker exec -it keylime-verifier keylime_tenant -c delete -t keylime-agent -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000
echo "\n\n"

# STEP 7: Add agent to tenant for monitoring (from verifier container) - Will run into an error that the TPM Quote is invalid for the nonce...
echo "Adding agent to tenant for monitoring..."
docker exec -it keylime-verifier keylime_tenant -c add -t keylime-agent -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000
echo "\n\n"

# STEP 8: Check agent status (shows registration and attestation info) - Will get an error that the agent exists in the registrar's database but not in the verifier's
echo "Checking agent status..."
docker exec -it keylime-verifier keylime_tenant -c status -u d432fbb3-d2f1-4a97-9ef7-75bd81c00000
