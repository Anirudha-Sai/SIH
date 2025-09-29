import eventlet
eventlet.monkey_patch()
import geopy
from flask import Flask, request, jsonify,render_template, json
from flask_cors import CORS
from flask_socketio import SocketIO, join_room, leave_room, send
import math
from geopy.distance import geodesic
from datetime import datetime
import sqlite3
import socket
import sys
import os
import threading
import time
from datetime import datetime, timedelta
from dotenv import load_dotenv
load_dotenv()



started_routes = {}
all_locations = []
all_drivers={}
user_count={"Student":0, "Driver":0, "Admin":0, "Unknown":0}

all_start_timings=json.loads(os.getenv("all_start_timings"))

PORT = 6104

# Check port availability
def is_port_in_use(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(("localhost", port)) == 0

if is_port_in_use(PORT):
    print(f"❌ Flask is already running on port {PORT}. Exiting.")
    sys.exit(1)

app = Flask(__name__)
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="eventlet")

# Database Functions
def init_db():
    conn = sqlite3.connect("database.db", check_same_thread=False)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS chat (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            room TEXT NOT NULL,
            sender TEXT NOT NULL,
            message TEXT NOT NULL,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()
    conn.close()
    conn = sqlite3.connect("database.db", check_same_thread=False)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS logs (
            route_number TEXT, 
            log_date date, 
            log_time time
        )
    """)
    conn.commit()
    conn.close()
    
    conn = sqlite3.connect("database.db", check_same_thread=False)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS user_count ( 
            Date date, 
            Student_count integer,
            Driver_count integer,
            Admin_count integer
        )
    """)
    conn.commit()
    conn.close()
    
init_db()


# Functions to be used later
def auto_start():
    print("Aurostart is started")
    while True:
        now_time = datetime.now()
        now_time_minutes = now_time.hour * 60 + now_time.minute  # Minutes since midnight
        min_wait = None

        # Calculate minimum wait time for all routes in all_start_timings
        for route, start_time_str in all_start_timings.items():
            start_hour, start_minute = map(int, start_time_str.split(":"))
            start_time = start_hour * 60 + start_minute
            if route in started_routes:
                continue  # Already started, skip
            if start_time <= now_time_minutes <= start_time + 2:
                # If driver is connected, trigger start
                if route in all_drivers:
                    print(f"Triggering start_locations for {route} at {now_time.strftime('%H:%M:%S')}")
                    start_locations(route)
                wait = 1  # Check again soon for other routes
            elif now_time_minutes < start_time:
                wait = start_time - now_time_minutes
            else:
                # Start time has passed for today, skip
                continue

            if min_wait is None or wait < min_wait:
                min_wait = wait

        if min_wait is not None and min_wait > 0:
            sleep_time = min_wait * 60
            print(f"[auto_start] Sleeping for {sleep_time // 60} min(s) ({sleep_time} seconds)")
        else:
            # Sleep till midnight
            tomorrow = now_time + timedelta(days=1)
            midnight = datetime.combine(tomorrow.date(), datetime.min.time())
            sleep_time = (midnight - now_time).total_seconds()
            print(f"[auto_start] No more routes today. Sleeping till midnight ({int(sleep_time)} seconds)")

        time.sleep(sleep_time)
thread = threading.Thread(target=auto_start, daemon=True)


def is_in_college(lon, lat):
    # COLLEGE=(17.539873, 78.386514)
    COLLEGE = (17.539885990830992, 78.38652028688297)
    return geodesic(COLLEGE, (lat, lon)).meters <= 400


def log_data(route_id):
    try:
        conn = sqlite3.connect("database.db", check_same_thread=False)
        cursor = conn.cursor()
        current_date = datetime.now().strftime("%Y-%m-%d")
        current_time = datetime.now().strftime("%H:%M:%S")

        # Step 1: Check if the bus is already logged today
        cursor.execute("""
            SELECT 1 FROM logs WHERE route_number = ? AND log_date = ?
        """, (route_id, current_date))

        exists = cursor.fetchone()  # Fetch result (None if f)

        # Step 2: If not logged, insert the new log
        if not exists:
            cursor.execute("""
                INSERT INTO logs 
                VALUES (?, ?, ?)
            """, (route_id, current_date, current_time))
            conn.commit()
            conn.close()
            print(f"Bus {route_id} logged at {current_time}")
            log_user_count()
        else:
            cursor.execute("""
                Update logs set log_time=? where route_number=? and log_date=?
            """, (current_time, route_id, current_date))
            print(f"Bus {route_id} already logged today. Updated time to {current_time}")
            conn.commit()
            conn.close()
    except sqlite3.Error as e:
        print(f"Error logging data: {e}")


def log_user_count():
    try:
        conn = sqlite3.connect("database.db", check_same_thread=False)
        cursor = conn.cursor()
        current_date = datetime.now().strftime("%Y-%m-%d")

        # Step 1: Check if today's counts already exist
        cursor.execute("""
            SELECT Student_count, Driver_count, Admin_count 
            FROM user_count 
            WHERE Date = ?
        """, (current_date,))
        
        result = cursor.fetchone()

        if result:
            # If row exists, update all counts
            updated_student = result[0] + user_count["Student"]
            updated_driver = result[1] + user_count["Driver"]
            updated_admin = result[2] + user_count["Admin"]

            cursor.execute("""
                UPDATE user_count 
                SET Student_count = ?, Driver_count = ?, Admin_count = ? 
                WHERE Date = ?
            """, (updated_student, updated_driver, updated_admin, current_date))
        else:
            # If row doesn't exist, insert a new one
            cursor.execute("""
                INSERT INTO user_count (Date, Student_count, Driver_count, Admin_count) 
                VALUES (?, ?, ?, ?)
            """, (current_date, user_count["Student"], user_count["Driver"], user_count["Admin"]))

        # Reset counts after logging
        user_count["Student"] = 0
        user_count["Driver"] = 0
        user_count["Admin"] = 0

        conn.commit()
        conn.close()

    except sqlite3.Error as e:
        print(f"Error logging data: {e}")


def get_key_by_value(d, target_value):
    for key, value in d.items():
        if value == target_value:
            return key
    return None


def start_locations(route):
    if not route:
        print("No route provided for Server start location request")
        return

    socket_id = all_drivers[route]    
    print(f"Admin start location requested for route: {route} and socket: {socket_id}")
    # Send Start to this specific socket
    print(f"Sending start to socket {socket_id} (route {route})")
    socketio.emit("server_start", {
        "message": "Started by administrator",
        "socket_id": socket_id,
        "route_id": route
    }, room=socket_id)
    print(f"Admin start location request satisified for route: {route} and socket: {socket_id}")




# Socket IO events
@socketio.on("connect")
def handle_connect():
    route_id = request.args.get("route_id", "Unkown")
    role= request.args.get("role")
    if role==None:
        role="Unknown"
    user_count[role] += 1   
    if role in ["Student", "Admin"]:
        print(f"A {role} connected for Route {route_id}!")
    socketio.emit("server_message", {"message": f"A {role} connected for Route {route_id}!"})
    route_id=None


@socketio.on("connected")
def handle_driver_connect(data):
    route_id = data["route_id"]
    sid = data["socket_id"]
    role = data["role"]
    #Add for other roles in future
    if role not in ["Driver"]:
        print(f"Invalid role {role} for driver connection. Expected 'Driver'.")
        return
    else:
        if route_id in all_drivers.keys():
            socketio.emit("server_message", {"message": f"Route {route_id} already connected!", "status": False})
        all_drivers[route_id] = sid
        print("All Drivers: ",all_drivers)
    socketio.emit("server_message", {"message": f"Route {route_id} connected!"})


@socketio.on("location_update")
def handle_location_update(data):
    from datetime import datetime
    time_now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"{time_now} Received location update:  ", data)
    route_id = data.get("route_id")
    latitude = data.get("latitude")
    longitude = data.get("longitude")
    heading = data.get("heading")  # New field
    status = data.get("status")  # New field
    sid=data.get("socket_id")
    
    existing_route = next((r for r in all_locations if r["route_id"] == route_id), None)
    if not existing_route and status != "stopped":
        all_locations.append({
            "route_id": route_id,
            "latitude": latitude,
            "longitude": longitude,
            "heading": heading,
            "status": status,
            "socketId": sid
        })
        started_routes[route_id] = sid
        print(f"New route started: {route_id} with socket {sid}")


    elif existing_route:
        if status == "stopped":
            all_locations.remove(existing_route)
        else:
            existing_route["latitude"] = latitude
            existing_route["longitude"] = longitude
            existing_route["heading"] = heading
            existing_route["status"] = status
            existing_route["socketId"] = sid
    # Emit updated data to all connected clients
    socketio.emit("location_update", existing_route)
    
    if is_in_college(longitude, latitude):
        print(f"Bus {route_id} is in college")
        log_data(route_id)
        socketio.emit("server_stop", {
            "message": "Disconnected by administrator",
            "socket_id": sid,
            "route_id": route_id
        }, room=sid)     
    return {"status": "received"}


@socketio.on("final_update")
def handle_final_update(data):
    print("Received location update in final update:  ",data)
    route_id = data.get("route_id")
    latitude = data.get("latitude")
    longitude = data.get("longitude")
    heading = data.get("heading")  # New field
    status = data.get("status")  # New field
    sid=data.get("socket_id")
    reason = data.get("reason")
    
    # Emit updated data to all connected clients
    socketio.emit("location_update", {
        "route_id": route_id,
        "latitude": latitude,
        "longitude": longitude,
        "heading": heading,  # Send heading to clients
        "status": "stopped"  # Send status to clients
    })    
    
    existing_route = next((r for r in all_locations if r["route_id"] == route_id), None)
    if existing_route:
        all_locations.remove(existing_route)
    
    if route_id in started_routes.keys():
        started_routes.pop(route_id, None)
    
    if is_in_college(longitude, latitude):
        print(f"Bus {route_id} is in college")
        log_data(route_id)
        socketio.emit("server_stop", {
            "message": "Disconnected by administrator",
            "socket_id": sid,
            "route_id": route_id
        }, room=sid) 

    return {"status": "received"}


@socketio.on("disconnect")
def handle_disconnect():
    print("Client disconnected",request)
    session_id = request.sid
    route_id=request.args.get("route_id", "Unknown")
    role= request.args.get("role")
    if role=="Driver":
        route_id = get_key_by_value(all_drivers, session_id)
    from datetime import datetime
    time_now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"{time_now} Session {session_id} disconnected for Route ID: {route_id}, Role: {role}")

    all_drivers.pop(route_id, None)
    started_routes.pop(route_id, None)

    print(f"All Drivers: {all_drivers}")
    socketio.emit("server_message", {"message": f"Route {route_id or 'Unknown'} disconnected!"})


@socketio.on("admin_start_location")
def handle_admin_start_location(data):
    socket_id = data.get("socket_id")
    if not socket_id:
        response = {"status": "error", "message": "No socket ID provided","socket_id": request.sid }
        socketio.emit("admin_start_location_response", response, room=request.sid)
        return
    
    print(f"Admin start location request for socket: {socket_id}")

    # Get the route ID for this socket
    route_id = get_key_by_value(all_drivers, socket_id)    
    
    # Send Start to this specific socket
    print(f"Sending start to socket {socket_id} (route {route_id})")
    socketio.emit("admin_start", {
        "message": "Started by administrator",
        "socket_id": socket_id,
        "route_id": route_id
    }, room=socket_id)

    # Send response back to admin
    response = {
        "status": "success", 
        "message": f"Start signal sent to socket {socket_id} (route {route_id})"
    }
    
    socketio.emit("admin_start_location_response", response)


@socketio.on("admin_stop_location")
def handle_admin_stop_location(data):
    socket_id = data.get("socket_id")    
    if not socket_id:
        print(f"Requested for {socket_id} but not found")
        response = {"status": "error", "message": "No socket ID provided","socket_id": request.sid }
        socketio.emit("admin_disconnect_response", response, room=request.sid)
        return
    
    # Debug info
    print(f"Admin disconnect request for socket: {socket_id}")
    
    route = get_key_by_value(all_drivers, socket_id)
    if not route:
        response = {"status": "error", "message": f"Socket ID {socket_id} not found","socket_id": request.sid }
        socketio.emit("admin_disconnect_response", response, room=request.sid)
        return
    
    if route in started_routes.keys():
        socketio.emit("admin_stop", {
            "message": "Disconnected by administrator",
            "socket_id": socket_id,
            "route_id": route
        }, room=socket_id)
        print(f"Sending force_disconnect to socket {socket_id} (route {route})")

    # Send response back to admin
    response = {
        "status": "success", 
        "message": f"Disconnect signal sent to socket {socket_id} (routkoe {route})"
    }
    socketio.emit("admin_stop_location_response", response)




@socketio.on("all_drivers")
def get_all_drivers(data=None):
    yet_to_start = {}
    for route, socket_id in all_drivers.items():
        if route not in started_routes:
            yet_to_start[route] = socket_id
    return yet_to_start


@socketio.on("all_locations")
def get_all_locations(data=None):
    return all_locations  # This sends data via the Socket.IO callback


@socketio.on("started_routes")
def get_started_routes():
    return started_routes


@socketio.on("join_room")
def handle_join(data):
    room = data["room"]
    sender = data["sender"]
    join_room(room)
    send({"sender": "System", "message": f"{sender} joined {room}"}, room=room)

    # Send chat history only to the joining client
    conn = sqlite3.connect("database.db", check_same_thread=False)
    cursor = conn.cursor()
    cursor.execute("SELECT sender, message, timestamp FROM chat WHERE room = ? ORDER BY timestamp ASC", (room,))
    messages = [{"sender": row[0], "message": row[1], "timestamp": row[2]} for row in cursor.fetchall()]
    conn.close()
    socketio.emit("chat_history", {"room": room, "messages": messages}, room=request.sid)


@socketio.on("leave_room")
def handle_leave(data):
    room = data["room"]
    sender = data["sender"]
    leave_room(room)
    send({"sender": "System", "message": f"{sender} left {room}"}, room=room)


@socketio.on("send_message")
def handle_message(data):
    room = data["room"]
    sender = data["sender"]
    message = data["message"]

    conn = sqlite3.connect("database.db", check_same_thread=False)
    cursor = conn.cursor()
    cursor.execute("INSERT INTO chat (room, sender, message) VALUES (?, ?, ?)", (room, sender, message))
    conn.commit()
    conn.close()

    socketio.emit("chat_message", {
        "sender": sender,
        "message": message,
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }, room=room)


if __name__ == "__main__":
    # thread.start()
    socketio.run(app, host="0.0.0.0", port=PORT, debug=True)
