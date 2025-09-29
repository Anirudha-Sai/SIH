
## Setup 

### One time setup

cd
python3 -m venv vjbus_env
source ~/vjbus_env/bin/activate
pip install eventlet flask flask_cors flask_socketio


### Code changesa
Use the IP generated say 10.45.8.187:3000 in the FE code. 

## Servers

This will serve the frontend server 

### How to start the BE Server  (Terminal 1)

cd ~/vj-servers/backend/be4-vjbus
source ~/vjbus_env/bin/activate

python3 server.py

