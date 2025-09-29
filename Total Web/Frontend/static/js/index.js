// ===== CONFIGURATION CONSTANTS =====
const API_URL = "https://dev-auth.vjstartup.com";
let socket; // Will be initialized after scripts are loaded

// ===== GLOBAL VARIABLES =====
let GOOGLE_CLIENT_ID = null;
let selectedRoute = localStorage.getItem("busApplicationSelectedRouteByStudent");
let latestBusLocation = null;
let markers = {};
let firstRecenter = {};
let map;
const fixedLatLng = [17.5,78.6];
let routes = []; // Initialize as empty array, will be populated from API
let activeRoutes = new Set();

// UI Elements
let trackBtn, homeBtn, chatBtn;
let trackingCard, routeSelect, findDistanceBtn, recenterBtn;
let connectionStatus, statusText, distanceTimeText, lastUpdatedText;

// Custom bus icon for map
let busIcon;

// ===== INITIALIZATION =====
document.addEventListener("DOMContentLoaded", async function() {
    console.log("DOM fully loaded, initializing application...");
    
    // First load all required scripts
    try {
        await loadAllScripts();
        
        // Initialize socket after script is loaded
        socket = io("wss://dev-bus.vjstartup.com", {
            transports: ["websocket"],
            reconnection: true,
            reconnectionAttempts: 5,
            reconnectionDelay: 1000,
            query: {
                route_id: selectedRoute, // replace with dynamic route ID if needed
                role: "Student"     // or "Student", etc.
            }
        });

        // Initialize map
        initializeMap();
        addFixedMarker();
        
        // Create bus icon after Leaflet is loaded
        busIcon = L.divIcon({
            className: 'bus-marker',
            html: '<div style="font-size: 25px;">🚌</div>',
            iconSize: [50, 50],
            iconAnchor: [15, 15]
        });
        
        // Get Google client ID
        await getGoogleClientId();
        
        // Get routes
        await getRoutes();
        
        // Initialize UI elements
        initializeUI();
        
        // Set up socket event handlers
        setupSocketEvents();
        
        // Update UI based on auth state
        updateLoginButton();
        fill_tracking_info();
        
        // Initialize Google Sign-In when GOOGLE_CLIENT_ID is available
        if (GOOGLE_CLIENT_ID) {
            initializeGoogleSignIn();
        }
        document.getElementById('floating-recenter-btn').onclick = function() {
            if (selectedRoute && markers[selectedRoute]) {
                let markerPosition = markers[selectedRoute].getLatLng();
                map.setView([markerPosition.lat - 0.008, markerPosition.lng], 13);
            }
        };

    } catch (error) {
        console.error("Error during initialization:", error);
    }
});

// ===== MAP FUNCTIONS =====
function initializeMap() {
    map = L.map('map', {
        center: fixedLatLng,
        zoom: 10,
        attributionControl: false  // Disable default attribution control
    });

    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        attribution: "",  // Prevent Leaflet from auto-adding OSM attribution
        updateWhenZooming: false,
        updateWhenIdle: true,
        reuseTiles: true
    }).addTo(map);

    // Custom attribution control without "Leaflet" prefix
    L.control.attribution({
        position: 'bottomright',
        prefix: false  // <- this removes "Leaflet"
    }).addTo(map);

    // Add your own attribution text
    map.attributionControl.addAttribution('VJ Bus | Map data © OpenStreetMap contributors');
}

function addFixedMarker() {
    if (!map) return;
    
    // const emojiIcon = L.divIcon({
    //     className: 'emoji-marker',
    //     html: '<div style="font-size: 25px;">📍</div>',
    //     iconSize: [70, 70],
    //     iconAnchor: [15, 15]
    // });
    // L.marker(fixedLatLng, { icon: emojiIcon }).addTo(map);
}

async function getRoutes() {
    try {
        console.log("Fetching routes...");
        const res = await fetch("/get-all-routes");
        const text = await res.text();
        routes = JSON.parse(text); // Assign to global `routes`
        console.log("Routes fetched:", routes);
    } catch (err) {
        console.error("Error fetching routes:", err);
        routes = []; // fallback to empty array
    }
    
    // After fetching routes, fetch active routes
    await fetchActiveRoutes();
}

async function fetchActiveRoutes() {
    console.log("Fetching active routes...");
    try {
        socket.emit("all_connections", null, (connections) => {
            if (!connections || connections.length === 0) {
                console.warn("No active connections found.");
                return;
            }

            console.log("Active connections received:", connections);

            activeRoutes.clear();
            connections.forEach(conn => {
                if (conn.status === "tracking_active") {
                    activeRoutes.add(conn.route_id);
                }
            });

            updateRouteDropdown();
        });
    } catch (error) {
        console.error("Error fetching active routes:", error);
        updateRouteDropdown(); // Still update dropdown with routes we have
    }
}

// ===== UTILITY FUNCTIONS =====
async function getGoogleClientId() {
    try {
        const res = await fetch('/get-google-client-id');
        const data = await res.json();
        GOOGLE_CLIENT_ID = data.apiKey;
        console.log("Google Client ID fetched successfully");
    } catch (error) {
        console.error("Error fetching Google Client ID", error);
    }
}

function loadScript(src, isAsync = true, isDefer = true) {
    return new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = src;
        if (isAsync) script.async = true;
        if (isDefer) script.defer = true;
        script.onload = () => resolve();
        script.onerror = () => reject(new Error(`Failed to load script: ${src}`));
        document.head.appendChild(script);
    });
}

function loadCSS(href) {
    return new Promise((resolve, reject) => {
        const link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = href;
        link.onload = () => resolve();
        link.onerror = () => reject(new Error(`Failed to load CSS: ${href}`));
        document.head.appendChild(link);
    });
}

async function loadAllScripts() {
    try {
        await loadCSS("https://unpkg.com/leaflet/dist/leaflet.css");
        await loadCSS("../static/css/index-styles.css");
        await loadScript("https://unpkg.com/leaflet/dist/leaflet.js", false, false);
        await loadScript("https://cdnjs.cloudflare.com/ajax/libs/socket.io/4.5.4/socket.io.js");
        await loadScript("https://accounts.google.com/gsi/client");
        console.log("All scripts and CSS loaded successfully");
    } catch (error) {
        console.error("Error loading scripts or CSS:", error);
        throw error;
    }
}

function getCookieValue(name) {
    const cookieString = document.cookie;
    const cookies = cookieString.split('; ');
    for (let i = 0; i < cookies.length; i++) {
        const cookie = cookies[i].split('=');
        if (cookie[0] === name) {
            return decodeURIComponent(cookie[1]);
        }
    }
    return null;
}

function decodeJwt(token) {
    try {
        if (!token || token.split('.').length !== 3) {
            // Return empty object instead of throwing error
            return {};
        }
        const base64Url = token.split('.')[1];
        const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
        const jsonPayload = decodeURIComponent(atob(base64).split('').map(c =>
            '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2)
        ).join(''));
        return JSON.parse(jsonPayload);
    } catch (error) {
        console.error("Error decoding JWT:", error);
        return {}; // Return empty object on any error
    }
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function setActive(element) {
    document.querySelectorAll(".menu-item").forEach((item) => item.classList.remove("active"));
    element.classList.add("active");
}

// ===== UI INITIALIZATION =====
function initializeUI() {
    // Assign DOM elements
    trackBtn = document.getElementById("trackBtn");
    homeBtn = document.getElementById("homeBtn");
    chatBtn = document.getElementById("chatBtn");
    trackingCard = document.getElementById("trackingCard");
    routeSelect = document.getElementById("routeSelect");
    findDistanceBtn = document.getElementById("find-distance");
    recenterBtn = document.getElementById("recenter");
    connectionStatus = document.getElementById("connection");
    statusText = document.getElementById("status");
    distanceTimeText = document.getElementById("distance-time");
    lastUpdatedText = document.getElementById("last-updated");
    
    if (!routeSelect) {
        console.error("routeSelect element not found in DOM!");
        return;
    }
    
    // Hide optional elements initially
    if (distanceTimeText) distanceTimeText.style.display = "none";
    if (lastUpdatedText) lastUpdatedText.style.display = "none";
    
    updateRouteDropdown();
    
    // Set up event listeners
    setupEventListeners();
}

function updateRouteDropdown() {
    console.log("Updating route dropdown...");
    if (!routeSelect) {
        console.error("routeSelect element not found!");
        return;
    }
    
    routeSelect.innerHTML = '<option value="">-- Select Route --</option>';
    routes.forEach((route) => {
        let option = document.createElement("option");
        option.value = route;
        option.textContent = activeRoutes.has(route) ? `${route} 🟢` : route;
        routeSelect.appendChild(option);
    });
    
    // Restore selected route if it exists
    if (selectedRoute) {
        routeSelect.value = selectedRoute;
    }
    
    console.log("Dropdown updated with", routes.length, "routes");
}

function setupEventListeners() {
    if (routeSelect) {
        routeSelect.addEventListener("change", function() {
            if (selectedRoute) {
                socket.emit("unsubscribe", selectedRoute);
            }
            selectedRoute = this.value;
            
            if (selectedRoute) {
                localStorage.setItem("busApplicationSelectedRouteByStudent", selectedRoute);
                socket.emit("subscribe", selectedRoute);
            } else {
                localStorage.removeItem("busApplicationSelectedRouteByStudent");
            }
            
            fill_tracking_info();
            
            if (statusText) {
                statusText.innerText === selectedRoute ? 
                    `Tracking ${selectedRoute}` : "Select a route to start tracking";
                console.log("stat",statusText.innerText)
            }
            
            // Hide elements initially
            if (findDistanceBtn) findDistanceBtn.style.display = "none";
            if (recenterBtn) recenterBtn.style.display = "none";
            if (distanceTimeText) distanceTimeText.style.display = "none";
            if (lastUpdatedText) lastUpdatedText.style.display = "none";
            
            // Remove previous markers
            for (const route in markers) {
                if (markers[route] && markers[route]._map) {
                    markers[route].remove();
                }
            }
        });
    }
    
    if (trackBtn) {
        trackBtn.addEventListener("click", function() {
            if (trackingCard) trackingCard.style.display = "block";
            setActive(this);
        });
    }
    
    if (homeBtn) {
        homeBtn.addEventListener("click", function() {
            if (trackingCard) trackingCard.style.display = "none";
            setActive(this);
        });
    }
    
    if (chatBtn) {
        chatBtn.addEventListener("click", function() {
            setActive(this);
            window.location.href = "https://dev-bus.vjstartup.com/chat";
        });
    }
    
    if (findDistanceBtn) {
        findDistanceBtn.addEventListener("click", function() {
            if (!latestBusLocation) return;
            getUserLocation((userLocation) => {
                if (userLocation) {
                    getDistanceTime(userLocation, latestBusLocation);
                }
            });
        });
    }
    
    if (recenterBtn) {
        recenterBtn.addEventListener("click", function() {
            if (selectedRoute && markers[selectedRoute]) {
                let markerPosition = markers[selectedRoute].getLatLng();
                map.setView([markerPosition.lat - 0.008, markerPosition.lng], 13);
            }
        });
    }
    
    // Modal click outside close
    window.onclick = function(event) {
        let modal = document.getElementById("loginModal");
        if (event.target === modal) closeModal();
    };
    
    // Restore saved route from localStorage
    const savedRoute = localStorage.getItem("busApplicationSelectedRouteByStudent");
    if (savedRoute && routes.includes(savedRoute) && routeSelect) {
        routeSelect.value = savedRoute;
        selectedRoute = savedRoute;
        if (socket) {
            socket.emit("subscribe", savedRoute);
        }
    }
}

// ===== AUTH FUNCTIONS =====
function updateLoginButton() {
    const btn = document.getElementById("login-logout");
    if (!btn) return;
    
    if (getCookieValue("user") !== null) {
        btn.innerHTML = "LogOut";
        btn.style.background = "red";
    } else {
        btn.innerHTML = "Login";
        btn.style.background = "green";
    }
}

function login_logout(event) {
    event.preventDefault();
    let loginBtn = document.getElementById("login-logout");
    if (!loginBtn) return;

    if (getCookieValue("user") !== null) {
        logout(event);
    } else {
        openModal();
        const rollLoginForm = document.getElementById("rollLoginForm");
        const loginChoice = document.getElementById("loginChoice");
        
        if (rollLoginForm) rollLoginForm.style.display = "none";
        if (loginChoice) loginChoice.style.display = "block";
    }
}

function handleCredentialResponse(response) {
    const token = response.credential;
    
    fetch(`${API_URL}/auth/google`, {
        method: "POST",
        credentials: "include",
        headers: {
            "Content-Type": "application/json"
        },
        body: JSON.stringify({ token })
    })
    .then(res => res.json())
    .then(data => {
        if (data.user) {
            fill_tracking_info();
            updateLoginButton();
            closeModal();
        } else {
            alert("❌ Login failed!");
        }
    })
    .catch(error => {
        console.error("Error during Google authentication:", error);
        alert("Error during login. Please try again.");
    });
}

async function logout(event) {
    event.preventDefault();
    const confirmLogout = confirm("Are you sure you want to log out..!!");
    if (!confirmLogout) return;
    
    try {
        await fetch(`${API_URL}/logout`, {
            method: "POST",
            credentials: "include"
        });
    } catch (error) {
        console.error("Error logging out:", error);
        alert("Error logging out");
    }
    
    await sleep(1);
    updateLoginButton();
    fill_tracking_info();
}

function initializeGoogleSignIn() {
    if (!GOOGLE_CLIENT_ID) {
        console.error("Google Client ID not available!");
        return;
    }
    
    try {
        google.accounts.id.initialize({
            client_id: GOOGLE_CLIENT_ID,
            callback: handleCredentialResponse,
            hosted_domain: "vnrvjiet.in",
            ux_mode: "popup"
        });
        
        const signInButton = document.getElementById("g_id_signin");
        if (signInButton) {
            google.accounts.id.renderButton(
                signInButton,
                { theme: "outline", size: "large" }
            );
        }
    } catch (error) {
        console.error("Error initializing Google Sign-In:", error);
    }
}

// ===== LOGIN MODAL FUNCTIONS =====
function openModal() {
    let modal = document.getElementById("loginModal");
    if (modal) modal.style.display = "block";
}

function closeModal() {
    let modal = document.getElementById("loginModal");
    if (modal) modal.style.display = "none";
}

function showRollLogin() {
    const loginChoice = document.getElementById("loginChoice");
    const rollLoginForm = document.getElementById("rollLoginForm");
    
    if (loginChoice) loginChoice.style.display = "none";
    if (rollLoginForm) rollLoginForm.style.display = "block";
}

function submitLogin(event) {
    event?.preventDefault();
    let rollNo = document.getElementById("rollNo")?.value;
    let password = document.getElementById("password")?.value;

    if (!rollNo || !password) {
        alert("⚠️ Enter Roll No and Password!");
        return;
    }

    let loginData = { roll_no: rollNo, password: password };
    if (socket) {
        socket.emit("login", loginData);
    } else {
        console.error("Socket not initialized!");
    }
}

function startGoogleLogin() {
    if (!google?.accounts?.id) {
        console.error("Google accounts API not loaded!");
        return;
    }
    
    google.accounts.id.prompt();
    
    const loginChoice = document.getElementById("loginChoice");
    const googleLoginForm = document.getElementById("googleLoginForm");
    const signInButton = document.getElementById("g_id_signin");
    
    if (loginChoice) loginChoice.style.display = "none";
    if (googleLoginForm) googleLoginForm.style.display = "block";
    
    if (signInButton) {
        google.accounts.id.renderButton(
            signInButton,
            { theme: "outline", size: "large" }
        );
    }
}

// ===== TRACKING FUNCTIONS =====
function fill_tracking_info() {    
    // Safely get user name from cookie or localStorage
    let userName = "";
    const userCookie = getCookieValue("user");
    let isLogged = false;
    
    if (userCookie) {
        isLogged = true;
        try {
            // Try to parse the cookie directly first
            const userData = JSON.parse(userCookie);
            userName = userData.family_name || "";
            
            // If no family_name in direct parsing, try JWT decoding
            if (!userName && userCookie.split('.').length === 3) {
                const decoded = decodeJwt(userCookie);
                userName = decoded.family_name || "";
            }
        } catch (e) {
            console.log("Error parsing user cookie", e);
        }
    }
    
    const sRoute = localStorage.getItem("busApplicationSelectedRouteByStudent") ? 
                  localStorage.getItem("busApplicationSelectedRouteByStudent").split(" ")[0] : "";
    let routeInfo = document.querySelector(".route_info");
    let chatBtn = document.getElementById("chatBtn");

    if (!routeInfo) return;

    if (sRoute !== "") {
        routeInfo.innerHTML = `Hello ${userName}👋 <br> Tracking ${sRoute} 🔴`;
    } else {
        routeInfo.innerHTML = `Hello ${userName}👋 <br>No Route Being Tracked 🔴`;
    }
    
    if (isLogged) {
        chatBtn.style.display = "block";
    } else {
        chatBtn.style.display = "none";
    }
}

function getUserLocation(callback) {
    if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition(
            (position) => {
                const lat = position.coords.latitude;
                const lon = position.coords.longitude;
                callback(`${lon},${lat}`);
            },
            (error) => {
                console.error("Error fetching user location", error);
                callback(null);
            }
        );
    } else {
        console.error("Geolocation is not supported by this browser.");
        callback(null);
    }
}

async function getDistanceTime(origin, destination) {
    try {
        const response = await fetch('/get-tom-tom-api-key');
        const data = await response.json();
        const apiKey = data.apiKey;
        
        if (typeof origin !== "string" || !origin.includes(",")) {
            console.error("Invalid origin format. Expected 'latitude,longitude'");
            return;
        }
        
        if (typeof destination !== "string" || !destination.includes(",")) {
            console.error("Invalid destination format. Expected 'latitude,longitude'");
            return;
        }
        
        const [originLng, originLat] = origin.split(",");
        const [destinationLng, destinationLat] = destination.split(",");
        
        const correctedOrigin = `${originLat},${originLng}`;
        const correctedDestination = `${destinationLat},${destinationLng}`;
        
        const url = `https://api.tomtom.com/routing/1/calculateRoute/${correctedOrigin}:${correctedDestination}/json?key=${apiKey}&traffic=true&routeType=fastest`;
        
        const routeResponse = await fetch(url);
        const routeData = await routeResponse.json();
        
        if (routeData.routes && routeData.routes.length > 0) {
            const route = routeData.routes[0].summary;
            const distance = (route.lengthInMeters / 1000).toFixed(2) + " km";
            const minutes = Math.floor(route.travelTimeInSeconds / 60);
            const seconds = route.travelTimeInSeconds % 60;
            const duration = `${minutes} min ${seconds} sec`;
            
            if (distanceTimeText) {
                distanceTimeText.innerText = `📏 Distance: ${distance} | ⏳ ETA: ${duration}`;
                distanceTimeText.style.display = "block";
            }
            
            if (lastUpdatedText) {
                lastUpdatedText.innerText = `Last updated: ${new Date().toLocaleTimeString()}`;
                lastUpdatedText.style.display = "block";
            }
        } else {
            console.warn("No route found!");
        }
    } catch (error) {
        console.error("❌ Error fetching TomTom Traffic API data:", error);
    }
}

function updateFindDistanceVisibility() {
    if (!findDistanceBtn ) return;
    
    if (latestBusLocation) {
        findDistanceBtn.style.display = "block";
        // recenterBtn.style.display = "block";
    } else {
        findDistanceBtn.style.display = "none";
        // recenterBtn.style.display = "none";
    }
}

// ===== SOCKET EVENTS =====
function setupSocketEvents() {
    socket.on("connect", () => {
        console.log("Connected to WebSocket server");
        if (connectionStatus) {
            connectionStatus.textContent = "Connected ✅";
            connectionStatus.style.color = "green";
        }
        
        // Resubscribe to selected route if exists
        if (selectedRoute) {
            socket.emit("subscribe", selectedRoute);
        }
    });
    
    socket.on("all_connections_update", function(connections) {
        console.log("Received all_connections_update:", connections);
        
        // Clear previous active routes
        activeRoutes.clear();
        
        // Update active routes based on received data
        connections.forEach(conn => {
            if (conn.status === "tracking_active") {
                activeRoutes.add(conn.route_id);
            }
        });
        
        // Update the dropdown with green dots
        updateRouteDropdown();
    });
    
    socket.on("connect_error", (error) => {
        console.error("WebSocket connection error:", error);
        if (statusText) {
            statusText.innerText = "Failed to connect to server";
        }
    });
    
    socket.on("disconnect", () => {
        console.log("Disconnected from WebSocket server");
        if (connectionStatus) {
            connectionStatus.textContent = "Disconnected ❌";
            connectionStatus.style.color = "red";
        }
        if (statusText) {
            statusText.innerText = "Disconnected from server";
        }
        
        // Clear active routes when disconnected
        activeRoutes.clear();
        updateRouteDropdown();
    });
    
    socket.on("subscribed", (route) => {
        console.log(`Subscribed to ${route}`);
        if (statusText) {
            statusText.innerText = `Tracking ${route} 🔴`;
        }
    });
    
    socket.on("unsubscribed", (route) => {
        console.log(`Unsubscribed from ${route}`);
    });
    
    socket.on("location_update", function(data) {
        if (!data.route_id) return;
        
        // Update route status in dropdown
        const routeOption = document.querySelector(`#routeSelect option[value='${data.route_id}']`);
        if (routeOption) {
            // Only update textContent if the status has changed
            if (data.status === "tracking_active" && !routeOption.textContent.includes("🟢")) {
                routeOption.textContent = `${data.route_id} 🟢`;
            } else if (data.status === "stopped" && routeOption.textContent.includes("🟢")) {
                routeOption.textContent = data.route_id;
            }
        }
        
        // Only process further if this is our selected route
        if (data.route_id !== selectedRoute) return;
        
        if (data.latitude && data.longitude && data.status === "tracking_active") {
            console.log("Received location update for selected route:", data);
            
            // Get user name from cookie, with fallback handling
            let userName = "";
            const userCookie = getCookieValue("user");
            if (userCookie) {
                try {
                    // Try direct JSON parsing first
                    const userData = JSON.parse(userCookie);
                    userName = userData.family_name || "";
                    
                    // If that fails, try JWT decoding if it looks like a JWT
                    if (!userName && userCookie.split('.').length === 3) {
                        const decoded = decodeJwt(userCookie);
                        userName = decoded.family_name || "";
                    }
                } catch (error) {
                    console.log("Error getting user name:", error);
                }
            }
            
            const routeInfo = document.querySelector(".route_info");
            if (routeInfo) {
                routeInfo.innerHTML = `Hello ${userName}👋 <br> Tracking ${selectedRoute.split(" (")[0]} 🟢`;
            }
            
            latestBusLocation = `${data.longitude},${data.latitude}`;
            updateFindDistanceVisibility();
            
            // Rest of the function remains the same...        
            if (!map) {
                console.error("Map not initialized!");
                return;
            }
            
            // Update marker on map
            if (!markers[selectedRoute]) {
                markers[selectedRoute] = L.marker([data.latitude, data.longitude], { icon: busIcon }).addTo(map);
            } else {
                markers[selectedRoute].setLatLng([data.latitude, data.longitude]);
                if (!markers[selectedRoute]._map) {
                    markers[selectedRoute].addTo(map);
                }
            }
            
            // Auto-center map on first update for this route
            if (!firstRecenter[selectedRoute]) {
                firstRecenter[selectedRoute] = true;
                map.setView([data.latitude, data.longitude], 13);
            }
        } else if (data.status === "stopped") {
            
            console.log("Bus tracking stopped for route:", data.route_id);
            let userName = "";
            const userCookie = getCookieValue("user");
            if (userCookie) {
                try {
                    // Try direct JSON parsing first
                    const userData = JSON.parse(userCookie);
                    userName = userData.family_name || "";
                    
                    // If that fails, try JWT decoding if it looks like a JWT
                    if (!userName && userCookie.split('.').length === 3) {
                        const decoded = decodeJwt(userCookie);
                        userName = decoded.family_name || "";
                    }
                } catch (error) {
                    console.log("Error getting user name:", error);
                }
            }
            const routeInfo = document.querySelector(".route_info");
            
            if (markers[selectedRoute] && markers[selectedRoute]._map) {
                markers[selectedRoute].remove();
                if (routeInfo) {
                    routeInfo.innerHTML = `Hello ${userName}👋 <br> Tracking ${selectedRoute.split(" (")[0]} 🔴`;
                }
            }
            
            firstRecenter[selectedRoute] = false;
            latestBusLocation = null;
            updateFindDistanceVisibility();
        }
    });
}