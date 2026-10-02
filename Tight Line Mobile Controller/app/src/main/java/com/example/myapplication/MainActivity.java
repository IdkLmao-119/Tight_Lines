package com.example.myapplication;

import android.annotation.SuppressLint;
import android.content.Context;
import android.content.SharedPreferences;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.net.DhcpInfo;
import android.net.wifi.WifiManager;
import android.os.Bundle;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.SocketTimeoutException;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;

// ============================================================================
// CONNECTION MANAGER (ANDROID SIDE)  — module 1 of 3
// ============================================================================
// This Activity IS the phone's connection manager: it owns the WebSocket
// connection to the PC, detects the three input types this project uses
// (swipe, tap, swing), and reports simple connection/ping status.
//
// The PC's address is NOT hardcoded — the player either types it in
// manually, or taps "Auto-Discover" to find it automatically via a UDP
// broadcast on the local network (see performDiscovery() below). This is
// what makes the app safe to distribute to other people's devices, since
// every player's PC will have a different IP address.
//
//   SWIPE — dragging a finger across the screen (GestureDetector.onFling)
//   TAP   — a quick press on the screen (GestureDetector.onSingleTapUp)
//   SWING — physically moving/swinging the phone (gyroscope spike detection)
//
// Requires, in app/build.gradle:
//     implementation("com.squareup.okhttp3:okhttp:4.12.0")
// And in AndroidManifest.xml, inside <manifest>, above <application>:
//     <uses-permission android:name="android.permission.INTERNET" />
//     <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
//
// ALSO REQUIRED (this was missing before): the connection uses plain ws://
// (not wss://), and Android 9+ blocks cleartext traffic by default. Add this
// attribute to the <application> tag in AndroidManifest.xml:
//     android:usesCleartextTraffic="true"
// Without it, connecting fails with "CLEARTEXT communication ... not permitted".
//
// TIP: if your Wi-Fi network has no internet (e.g. a PC-hosted hotspot),
// Android may route app traffic over mobile data, which cannot reach the
// PC's 192.168.x.x address. Turn mobile data off while testing.
// ============================================================================

public class MainActivity extends AppCompatActivity implements SensorEventListener {

    // --- Networking ---
    // IMPORTANT: readTimeout/writeTimeout are explicitly disabled (set to
    // 0 = no timeout) here. OkHttp's default 10-second read timeout is
    // meant for regular one-off HTTP requests, NOT a persistent WebSocket
    // connection that's supposed to sit open and wait indefinitely for the
    // next message. Leaving the default active can cause the connection to
    // be killed as "timed out" during any quiet gap longer than 10 seconds
    // (e.g. the player just isn't moving the phone right now). pingInterval
    // is what actually keeps the connection alive/monitored instead.
    private final OkHttpClient client = new OkHttpClient.Builder()
            .pingInterval(15, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .writeTimeout(0, TimeUnit.MILLISECONDS)
            .build();

    private WebSocket webSocket;

    // No hardcoded server address anymore — this is filled in at runtime,
    // either by the player typing it into serverIpInput, or automatically
    // by performDiscovery() below.
    private String serverUrl = null;

    // The port your ConnectionManager.gd listens on — this stays constant
    // even though the IP address varies per PC.
    private static final int SERVER_PORT = 9080;

    // --- Auto-discovery settings ---
    // A separate, fixed port used ONLY for the discovery broadcast/response
    // — kept different from SERVER_PORT so discovery traffic and game
    // traffic never get confused with each other.
    private static final int DISCOVERY_PORT = 9081;

    // The exact text the phone broadcasts, and that ConnectionManager.gd
    // listens for. Both sides must agree on this exact string.
    private static final String DISCOVERY_MESSAGE = "DISCOVER_FISHING_SERVER";

    // How long to wait for a PC to respond before giving up.
    private static final int DISCOVERY_TIMEOUT_MS = 3000;

    // --- Connection / ping status ---
    // Tracks whether the WebSocket connection is currently open.
    private boolean isConnected = false;

    // Stores the most recently measured round-trip ping time, in milliseconds.
    // NOTE: this is only ever set if you wire up an actual ping/pong
    // round-trip (see the note at the bottom of this file) — as written,
    // it stays at -1 (unknown) since no round-trip measurement exists yet.
    private long latencyMs = -1;

    // --- Sensors ---
    private SensorManager sensorManager;
    private Sensor gyroSensor;

    // --- Swing detection tuning ---
    // A swing is detected as a spike in rotation speed. SWING_THRESHOLD is
    // how fast (in radians/second) the phone must be rotating to count as
    // an intentional swing rather than normal handling/jitter.
    private static final float SWING_THRESHOLD = 4.0f;

    // After detecting a swing, we wait this long before allowing another
    // one to be detected — this "cooldown" stops one physical swing motion
    // from being counted as many separate swings in a row.
    private static final long SWING_COOLDOWN_MS = 500L;
    private long lastSwingTimeMs = 0L;

    // A permanent, unique ID for THIS phone, generated once and saved
    // forever afterward — this is how the PC recognizes "this is the same
    // device as before" even if its IP address changes between sessions.
    private String deviceId;

    // --- UI ---
    private TextView statusText;
    private EditText serverIpInput;
    private Button connectButton;
    private Button discoverButton;
    private GestureDetector gestureDetector;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        statusText = findViewById(R.id.statusText);
        serverIpInput = findViewById(R.id.serverIpInput);
        connectButton = findViewById(R.id.connectButton);
        discoverButton = findViewById(R.id.discoverButton);

        deviceId = getOrCreateDeviceId();

        // Manual entry: player types an IP and taps Connect.
        connectButton.setOnClickListener(v -> {
            String ip = serverIpInput.getText().toString().trim();
            if (ip.isEmpty()) {
                Toast.makeText(this, "Enter an IP address first", Toast.LENGTH_SHORT).show();
                return;
            }
            connectToServer(ip);
        });

        // Auto-discover: finds the PC's IP automatically, no typing needed.
        discoverButton.setOnClickListener(v -> performDiscovery());

        // GestureDetector is Android's built-in helper for recognizing
        // common touch patterns (taps, swipes/flings, etc.) so we don't have
        // to manually track finger movement math ourselves.
        gestureDetector = new GestureDetector(this, new GestureListener());

        sensorManager = (SensorManager) getSystemService(SENSOR_SERVICE);
        gyroSensor = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE);

        // NOTE: connectToServer() is no longer called automatically here —
        // we wait for the player to either type an IP or use Auto-Discover,
        // since we no longer have any address to connect to by default.
    }

    // Forwards all touch events on the whole screen to the GestureDetector,
    // which figures out whether they form a tap, swipe, etc.
    @SuppressLint("ClickableViewAccessibility")
    @Override
    public boolean onTouchEvent(MotionEvent event) {
        gestureDetector.onTouchEvent(event);
        return true;
    }

    // ------------------------------------------------------------------------
    // PERSISTENT DEVICE ID
    // ------------------------------------------------------------------------
    // SharedPreferences is Android's built-in simple key-value storage that
    // survives app restarts (and even phone restarts) — it only goes away
    // if the app is uninstalled. We use it to store one random ID, created
    // the very first time the app runs, and reused every time after that.
    private String getOrCreateDeviceId() {
        SharedPreferences prefs = getSharedPreferences("controller_prefs", MODE_PRIVATE);
        String existingId = prefs.getString("device_id", null);

        if (existingId != null) {
            return existingId; // already had one — reuse it
        }

        // First launch ever — generate a new random unique ID and save it
        // permanently so every future launch finds it above instead.
        String newId = UUID.randomUUID().toString();
        prefs.edit().putString("device_id", newId).apply();
        return newId;
    }

    // ------------------------------------------------------------------------
    // CONNECTION MANAGEMENT
    // ------------------------------------------------------------------------
    private void connectToServer(String ip) {
        // FIX: close any previous connection first, so tapping Connect (or
        // Auto-Discover) more than once doesn't leave stale sockets open,
        // which the PC would see as duplicate connections.
        if (webSocket != null) {
            webSocket.close(1000, "Reconnecting");
            webSocket = null;
        }
        isConnected = false;

        serverUrl = "ws://" + ip + ":" + SERVER_PORT;
        Request request = new Request.Builder().url(serverUrl).build();

        runOnUiThread(() -> statusText.setText("Connecting to " + ip + "..."));

        webSocket = client.newWebSocket(request, new WebSocketListener() {
            @Override
            public void onOpen(WebSocket ws, Response response) {
                isConnected = true;
                runOnUiThread(() -> statusText.setText(getConnectionStatus()));

                JSONObject msg = new JSONObject();
                try {
                    msg.put("type", "connected");
                    msg.put("device_id", deviceId);
                } catch (JSONException e) {
                    e.printStackTrace();
                }
                sendMessage(msg);
            }

            @Override
            public void onFailure(WebSocket ws, Throwable t, Response response) {
                isConnected = false;
                String reason = t.getMessage();
                if (t.getCause() != null) reason += " / " + t.getCause().getMessage();
                final String shown = reason;
                runOnUiThread(() -> statusText.setText("Connection failed: " + shown));
            }

            @Override
            public void onClosed(WebSocket ws, int code, String reason) {
                isConnected = false;
                runOnUiThread(() -> statusText.setText(getConnectionStatus()));
            }
        });
    }

    // ------------------------------------------------------------------------
    // AUTO-DISCOVERY
    // ------------------------------------------------------------------------
    // Computes this phone's ACTUAL subnet broadcast address (e.g.
    // 192.168.137.255 for a typical /24 hotspot network), rather than
    // relying only on the generic 255.255.255.255 address. This matters
    // because 255.255.255.255 is known to be unreliable on Android — some
    // devices/Wi-Fi stacks don't route it out onto the Wi-Fi interface
    // correctly, whereas a network's own specific directed broadcast
    // address is delivered far more consistently.
    //
    // Requires android.permission.ACCESS_WIFI_STATE in AndroidManifest.xml.
    private List<InetAddress> getBroadcastAddresses() {
        List<InetAddress> addresses = new ArrayList<>();

        try {
            WifiManager wifiManager =
                    (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
            DhcpInfo dhcp = wifiManager.getDhcpInfo();

            if (dhcp != null && dhcp.ipAddress != 0 && dhcp.netmask != 0) {
                // Standard bitwise trick: (ip AND netmask) gives the network
                // address, then OR-ing with the INVERSE of the netmask fills
                // in the "host" bits with 1s, producing the broadcast address.
                int broadcastInt = (dhcp.ipAddress & dhcp.netmask) | ~dhcp.netmask;

                // Android stores these ints in little-endian byte order,
                // opposite of standard network byte order, so we extract
                // each byte manually with bit-shifting rather than using
                // a direct int-to-bytes conversion.
                byte[] quads = new byte[4];
                for (int k = 0; k < 4; k++) {
                    quads[k] = (byte) ((broadcastInt >> (k * 8)) & 0xFF);
                }
                addresses.add(InetAddress.getByAddress(quads));
            }
        } catch (Exception e) {
            // If anything goes wrong computing the specific address, we
            // still have the generic fallback added below.
            e.printStackTrace();
        }

        // Always include the generic broadcast address too, as a fallback
        // — harmless to try both, and covers networks/devices where the
        // specific address computation above doesn't apply cleanly.
        try {
            addresses.add(InetAddress.getByName("255.255.255.255"));
        } catch (IOException e) {
            e.printStackTrace();
        }

        return addresses;
    }

    // Sends a UDP broadcast onto the local network asking "is there a game
    // server here?" and listens briefly for a reply containing the PC's IP.
    // This works for BOTH connectivity modes (PC-hosted hotspot or shared
    // LAN) since in either case, phone and PC share the same local network
    // segment, and UDP broadcasts reach every device on that segment.
    //
    // This must run on a background thread — Android does not allow network
    // operations (even simple ones like this) on the main/UI thread, since
    // they could block the app from responding and freeze the interface.
    private void performDiscovery() {
        runOnUiThread(() -> statusText.setText("Searching for PC..."));

        new Thread(() -> {
            try (DatagramSocket socket = new DatagramSocket()) {
                socket.setBroadcast(true);
                socket.setSoTimeout(DISCOVERY_TIMEOUT_MS);

                byte[] sendData = DISCOVERY_MESSAGE.getBytes();

                // Send to every candidate broadcast address (the computed
                // subnet-specific one AND the generic 255.255.255.255) —
                // only one needs to actually reach the PC.
                // FIX: each send is wrapped individually. Before, if ONE
                // address failed (255.255.255.255 often throws on some
                // devices), the whole discovery aborted even though the
                // other broadcast had already been sent successfully.
                boolean anySent = false;
                IOException lastSendError = null;
                for (InetAddress addr : getBroadcastAddresses()) {
                    try {
                        DatagramPacket sendPacket = new DatagramPacket(
                                sendData, sendData.length, addr, DISCOVERY_PORT
                        );
                        socket.send(sendPacket);
                        anySent = true;
                    } catch (IOException sendError) {
                        lastSendError = sendError;
                    }
                }
                if (!anySent && lastSendError != null) {
                    throw lastSendError;
                }

                // Wait for a reply. ConnectionManager.gd sends back a plain
                // text string like "192.168.137.1" when it hears our request.
                byte[] receiveBuffer = new byte[256];
                DatagramPacket receivePacket = new DatagramPacket(receiveBuffer, receiveBuffer.length);
                socket.receive(receivePacket); // blocks until a reply arrives, or times out

                // FIX: use the reply packet's SOURCE address as the PC's IP.
                // That is, by definition, an address the phone just
                // successfully received traffic from, so it is far more
                // reliable than trusting the PC's own guess in the text.
                // The text payload is only used as a fallback.
                String discoveredIp = receivePacket.getAddress().getHostAddress();
                if (discoveredIp == null || discoveredIp.isEmpty()) {
                    discoveredIp = new String(
                            receivePacket.getData(), 0, receivePacket.getLength()
                    ).trim();
                }
                final String foundIp = discoveredIp;

                runOnUiThread(() -> {
                    serverIpInput.setText(foundIp);
                    statusText.setText("Found PC at " + foundIp);
                    connectToServer(foundIp);
                });

            } catch (SocketTimeoutException e) {
                runOnUiThread(() -> {
                    statusText.setText("No PC found — try entering the IP manually");
                    Toast.makeText(this, "Discovery timed out", Toast.LENGTH_SHORT).show();
                });
            } catch (IOException e) {
                runOnUiThread(() -> statusText.setText("Discovery error: " + e.getMessage()));
            }
        }).start();
    }

    private void sendMessage(JSONObject json) {
        if (webSocket != null) {
            webSocket.send(json.toString());
        }
    }

    // Returns a simple human-readable string describing connection status.
    public String getConnectionStatus() {
        return isConnected ? "Connected" : "Not connected";
    }

    // Returns a simple human-readable string describing the last known ping.
    // See the NOTE at the bottom of this file — latencyMs is only populated
    // once an actual ping/pong round trip is implemented.
    public String getPingStatus() {
        if (latencyMs < 0) {
            return "Ping: unknown";
        } else {
            return "Ping: " + latencyMs + "ms";
        }
    }

    // ------------------------------------------------------------------------
    // TOUCH INPUT: tap and swipe, handled via GestureDetector callbacks
    // ------------------------------------------------------------------------
    private class GestureListener extends GestureDetector.SimpleOnGestureListener {

        // Required override — must return true for other gesture callbacks
        // (like onFling) to actually fire.
        @Override
        public boolean onDown(MotionEvent e) {
            return true;
        }

        // Fires on a quick, precise press-and-release: a TAP.
        @Override
        public boolean onSingleTapUp(MotionEvent e) {
            // Normalize the tap position to a 0.0–1.0 range based on screen
            // size, so the PC doesn't need to know this phone's specific
            // screen resolution to make sense of the coordinates.
            float normalizedX = e.getX() / getResources().getDisplayMetrics().widthPixels;
            float normalizedY = e.getY() / getResources().getDisplayMetrics().heightPixels;

            JSONObject msg = new JSONObject();
            try {
                msg.put("type", "tap");
                msg.put("x", normalizedX);
                msg.put("y", normalizedY);
            } catch (JSONException ex) {
                ex.printStackTrace();
            }
            sendMessage(msg);
            return true;
        }

        // Fires when a finger drags across the screen and lifts off with
        // some speed: a SWIPE. (A slow drag that just stops doesn't count
        // as a "fling" — that's intentional, it filters out accidental drags.)
        @Override
        public boolean onFling(MotionEvent e1, MotionEvent e2, float velocityX, float velocityY) {
            if (e1 == null) return false;

            float dx = e2.getX() - e1.getX();
            float dy = e2.getY() - e1.getY();

            // Figure out the dominant direction by comparing how far the
            // swipe moved horizontally vs vertically.
            String direction;
            if (Math.abs(dx) > Math.abs(dy)) {
                direction = (dx > 0) ? "right" : "left";
            } else {
                direction = (dy > 0) ? "down" : "up";
            }

            JSONObject msg = new JSONObject();
            try {
                msg.put("type", "swipe");
                msg.put("direction", direction);
                msg.put("dx", dx);
                msg.put("dy", dy);
            } catch (JSONException ex) {
                ex.printStackTrace();
            }
            sendMessage(msg);
            return true;
        }
    }

    // ------------------------------------------------------------------------
    // GYROSCOPE INPUT: swing detection
    // ------------------------------------------------------------------------
    // Unlike tap/swipe (single discrete events from Android's gesture
    // system), the gyroscope streams continuous data many times per second.
    // We watch that stream ourselves and decide when it looks like an
    // intentional "swing" happened.
    @Override
    public void onSensorChanged(SensorEvent event) {
        if (event.sensor.getType() != Sensor.TYPE_GYROSCOPE) return;

        // Combine rotation speed on all 3 axes into one overall "how fast
        // is this phone rotating right now" number, using the standard
        // 3D magnitude formula: sqrt(x² + y² + z²).
        float x = event.values[0];
        float y = event.values[1];
        float z = event.values[2];
        double magnitude = Math.sqrt(x * x + y * y + z * z);

        if (magnitude < SWING_THRESHOLD) return; // too gentle — ignore

        long now = System.currentTimeMillis();
        if (now - lastSwingTimeMs < SWING_COOLDOWN_MS) return; // still cooling down

        lastSwingTimeMs = now;

        JSONObject msg = new JSONObject();
        try {
            msg.put("type", "swing");
            msg.put("magnitude", magnitude);
        } catch (JSONException ex) {
            ex.printStackTrace();
        }
        sendMessage(msg);
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int accuracy) {
        // Not needed for this use case.
    }

    // --- Lifecycle ---
    @Override
    protected void onResume() {
        super.onResume();
        if (gyroSensor != null) {
            sensorManager.registerListener(this, gyroSensor, SensorManager.SENSOR_DELAY_GAME);
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        sensorManager.unregisterListener(this);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (webSocket != null) {
            webSocket.close(1000, "App closed");
        }
    }

    // ============================================================================
    // NOTE ON PING MEASUREMENT
    // ============================================================================
    // latencyMs is currently never set to a real value. To measure actual
    // round-trip ping:
    //   1. Record System.currentTimeMillis() right before sending a small
    //      {"type": "ping"} message.
    //   2. Have the PC-side ConnectionManager.gd echo back a matching
    //      {"type": "pong"} message immediately upon receiving "ping".
    //   3. When that "pong" arrives (in a message-received callback), take
    //      a new System.currentTimeMillis() and subtract the timestamp from
    //      step 1 — the result is your round-trip latencyMs.
    // ============================================================================
}