
## Setup 

### One time setup

cd
python3 -m venv vjbus_env
source ~/vjbus_env/bin/activate
pip install eventlet flask flask_cors flask_socketio

### Code changes for Dev environment

#### For Production Environment 

driver.html & index.html : const socket = io("ws://103.248.208.119:3000"

#### For Developer Environment 
driver.html & index.html : const socket = io("ws://10.45.8.187:3000"

## Servers

Ensure to run the BE server from  ~/vj-servers/backend/be4-vjbus

### How to start the FE Server  (Terminal 2)

cd /home/kp/vj-servers/frontend/fe4-vjbus
python3 app.py 


### Browser

Passinger page
http://10.45.8.187:4000/

Driver Page
http://10.45.8.187:4000/driver
