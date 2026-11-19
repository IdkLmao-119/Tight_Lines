package com.example.myapplication;

import android.annotation.SuppressLint;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.net.DhcpInfo;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.VibrationEffect;
import android.text.Editable;
import android.text.TextWatcher;
import android.util.Log;
import android.os.Vibrator;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.Surface;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import com.google.android.material.button.MaterialButton;

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
import okio.ByteString;

public class MainActivity extends AppCompatActivity implements SensorEventListener {

    private final OkHttpClient client = new OkHttpClient.Builder()
            .pingInterval(15, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .writeTimeout(0, TimeUnit.MILLISECONDS)
            .build();

    private WebSocket webSocket;

    private static final long RECONNECT_DELAY_MS = 2000L;
    private static final long AUTO_DISCOVER_INTERVAL_MS = 3500L;
    private static final String PREF_LAST_IP = "last_pc_ip";
    private static final String PREF_PLAYER_NAME = "player_name";
    private static final int MAX_PLAYER_NAME_LENGTH = 18;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private Runnable reconnectRunnable;
    private Runnable autoDiscoverRunnable;
    private String lastIp = null;
    private boolean wantConnected = false;
    private int connectionAttempt = 0;
    private volatile boolean isDiscovering = false;
    private boolean triedSavedIpThisCycle = false;
    private int reconnectFailureCount = 0;

    private String serverUrl = null;
    private static final int SERVER_PORT = 9080;
    private static final int DISCOVERY_PORT = 9081;
    private static final String DISCOVERY_MESSAGE = "DISCOVER_FISHING_SERVER";
    private static final int DISCOVERY_TIMEOUT_MS = 3000;

    private boolean isConnected = false;
    private long latencyMs = -1;

    private SensorManager sensorManager;
    private Sensor gyroSensor;
    private Sensor accelSensor;

    private static final long TILT_SEND_INTERVAL_MS = 50L;
    private static final float TILT_FULL_ANGLE_DEG = 20f;
    // Dynamic sensitivity: TILT_FILTER_ALPHA range 0.70f (high sens / fast) to 0.95f (low sens / heavy smooth)
    private float tiltFilterAlpha = 0.8f;
    private static final long TILT_HOLD_AFTER_SWING_MS = 100L; // Reduced so tilt recovers quickly after a cast

    private final float[] gravity = new float[3];
    private boolean gravityInitialized = false;
    private long lastTiltSentMs = 0L;

    // Dynamic sensitivity: SWING_THRESHOLD range 12.0f (high sens / easier) to 16.0f (low sens / harder)
    private float swingThreshold = 12.0f;
    private static final long SWING_COOLDOWN_MS = 500L;
    private long lastSwingTimeMs = 0L;

    private static final long SWING_PEAK_WINDOW_MS = 120L;
    private boolean swingWindowOpen = false;
    private long swingWindowStartMs = 0L;
    private double swingPeak = 0.0;

    private String deviceId;

    private enum AppState { CONNECTION, OVERWORLD, CASTING, REELING, MENU }
    private AppState currentState = null;
    private AppState underlyingGameState = AppState.OVERWORLD;
    private String activeMenu = "none";
    private String assignedPlayerName = "";
    private String assignedScreenSide = "";

    private TextView statusText;
    private TextView connectionSubtext;
    private ProgressBar connectingSpinner;
    private EditText playerNameInput;
    private EditText serverIpInput;
    private Button connectButton;
    private Button discoverButton;
    private GestureDetector gestureDetector;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        deviceId = getOrCreateDeviceId();
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        reconnectRunnable = () -> {
            if (wantConnected && !isConnected && lastIp != null) {
                connectToServer(lastIp);
            }
        };

        autoDiscoverRunnable = () -> {
            if (currentState == AppState.CONNECTION && !isConnected) {
                startAutoDiscovery(false);
            }
        };

        gestureDetector = new GestureDetector(this, new GestureListener());
        sensorManager = (SensorManager) getSystemService(SENSOR_SERVICE);
        gyroSensor = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE);
        accelSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);

        switchToState(AppState.CONNECTION);
    }

    private void switchToState(AppState newState) {
        if (currentState == newState) return;
        currentState = newState;

        runOnUiThread(() -> {
            FrameLayout rootContainer = findViewById(R.id.rootContainer);
            rootContainer.removeAllViews();

            int layoutResId;
            switch (newState) {
                case CONNECTION:
                    layoutResId = R.layout.view_connection;
                    break;
                case OVERWORLD:
                    layoutResId = R.layout.view_overworld;
                    break;
                case CASTING:
                    layoutResId = R.layout.view_casting;
                    break;
                case REELING:
                    layoutResId = R.layout.view_reeling;
                    break;
                case MENU:
                    layoutResId = R.layout.view_menu;
                    break;
                default:
                    layoutResId = R.layout.view_connection;
                    break;
            }

            getLayoutInflater().inflate(layoutResId, rootContainer, true);

            if (newState == AppState.CONNECTION) {
                setupConnectionUI();
            } else {
                setupMenuHeaderButtons();

                if (newState == AppState.OVERWORLD) {
                    DPadView dpadView = findViewById(R.id.dpadView);
                    if (dpadView != null) {
                        dpadView.setOnMoveListener((x, y) -> {
                            JSONObject msg = new JSONObject();
                            try {
                                msg.put("type", "move");
                                msg.put("x", x);
                                msg.put("y", y);
                            } catch (JSONException e) {
                                e.printStackTrace();
                            }
                            sendMessage(msg);
                        });
                    }

                    Button btnInteract = findViewById(R.id.btnInteract);
                    if (btnInteract != null) {
                        btnInteract.setOnClickListener(v -> {
                            JSONObject msg = new JSONObject();
                            try {
                                msg.put("type", "interact");
                            } catch (JSONException e) {
                                e.printStackTrace();
                            }
                            sendMessage(msg);
                        });
                    }
                } else if (newState == AppState.REELING) {
                    FishingReelView reelView = findViewById(R.id.fishingReelView);
                    if (reelView != null) {
                        reelView.setOnReelListener(deltaDegrees -> {
                            JSONObject msg = new JSONObject();
                            try {
                                msg.put("type", "reel");
                                msg.put("delta", deltaDegrees);
                            } catch (JSONException e) {
                                e.printStackTrace();
                            }
                            sendMessage(msg);
                        });
                    }
                } else if (newState == AppState.MENU) {
                    setupMenuControlsUI();
                }

                updatePlayerIdentityBadge();
                sendScreenState();
            }
        });
    }

    private void setupMenuHeaderButtons() {
        Button btnFishBox = findViewById(R.id.btnFishBox);
        Button btnAlmanac = findViewById(R.id.btnAlmanac);
        Button btnEquipment = findViewById(R.id.btnEquipment);

        if (btnFishBox != null) btnFishBox.setOnClickListener(v -> sendMenuAction("fish_box"));
        if (btnAlmanac != null) btnAlmanac.setOnClickListener(v -> sendMenuAction("almanac"));
        if (btnEquipment != null) btnEquipment.setOnClickListener(v -> sendMenuAction("equipment"));

        styleMenuHeaderButtons();
    }

    private void styleMenuHeaderButtons() {
        MaterialButton btnFishBox = findViewById(R.id.btnFishBox);
        MaterialButton btnAlmanac = findViewById(R.id.btnAlmanac);
        MaterialButton btnEquipment = findViewById(R.id.btnEquipment);

        applyHeaderButtonStyle(btnFishBox, "fish_box".equals(activeMenu), "#D95D48", "#FFF9EE");
        applyHeaderButtonStyle(btnAlmanac, "almanac".equals(activeMenu), "#2A9D8F", "#FFF9EE");
        applyHeaderButtonStyle(btnEquipment, "equipment".equals(activeMenu), "#F4C95D", "#3B2312");
    }

    private void applyHeaderButtonStyle(MaterialButton btn, boolean isActive, String activeHex, String activeTextHex) {
        if (btn == null) return;
        if (isActive) {
            btn.setBackgroundTintList(ColorStateList.valueOf(Color.parseColor(activeHex)));
            btn.setTextColor(Color.parseColor(activeTextHex));
            btn.setStrokeColor(ColorStateList.valueOf(Color.parseColor("#FFF9EE")));
            btn.setStrokeWidth(5);
        } else {
            btn.setBackgroundTintList(ColorStateList.valueOf(Color.parseColor("#6C4527")));
            btn.setTextColor(Color.parseColor("#FFF3DC"));
            btn.setStrokeColor(ColorStateList.valueOf(Color.parseColor("#C89B6E")));
            btn.setStrokeWidth(2);
        }
    }

    private void setupMenuControlsUI() {
        Button btnUp = findViewById(R.id.btnNavUp);
        Button btnDown = findViewById(R.id.btnNavDown);
        Button btnLeft = findViewById(R.id.btnNavLeft);
        Button btnRight = findViewById(R.id.btnNavRight);
        Button btnSelect = findViewById(R.id.btnMenuSelect);
        Button btnBack = findViewById(R.id.btnMenuBack);
        Button btnTabPrev = findViewById(R.id.btnTabPrev);
        Button btnTabNext = findViewById(R.id.btnTabNext);

        if (btnUp != null) btnUp.setOnClickListener(v -> sendMenuAction("up"));
        if (btnDown != null) btnDown.setOnClickListener(v -> sendMenuAction("down"));
        if (btnLeft != null) btnLeft.setOnClickListener(v -> sendMenuAction("left"));
        if (btnRight != null) btnRight.setOnClickListener(v -> sendMenuAction("right"));
        if (btnSelect != null) btnSelect.setOnClickListener(v -> sendMenuAction("select"));
        if (btnBack != null) btnBack.setOnClickListener(v -> sendMenuAction("back"));
        if (btnTabPrev != null) btnTabPrev.setOnClickListener(v -> sendMenuAction("tab_prev"));
        if (btnTabNext != null) btnTabNext.setOnClickListener(v -> sendMenuAction("tab_next"));

        refreshMenuUI();
    }

    private void refreshMenuUI() {
        styleMenuHeaderButtons();
        if (currentState != AppState.MENU) return;

        TextView menuTitle = findViewById(R.id.menuTitle);
        TextView menuHint = findViewById(R.id.menuHint);
        LinearLayout menuTabBar = findViewById(R.id.menuTabBar);
        Button btnTabPrev = findViewById(R.id.btnTabPrev);
        Button btnTabNext = findViewById(R.id.btnTabNext);
        Button btnSelect = findViewById(R.id.btnMenuSelect);

        if (menuTitle == null || menuHint == null) return;

        switch (activeMenu) {
            case "almanac":
                menuTitle.setText("ALMANAC");
                menuHint.setText("D-Pad: Browse Fish  •  View: Open Entry");
                if (menuTabBar != null) menuTabBar.setVisibility(View.VISIBLE);
                if (btnTabPrev != null) btnTabPrev.setText("< Prev Area");
                if (btnTabNext != null) btnTabNext.setText("Next Area >");
                if (btnSelect != null) btnSelect.setText("VIEW");
                break;
            case "fish_box":
                menuTitle.setText("FISH BOX");
                menuHint.setText("D-Pad: Browse Slots  •  Inspect: Check Fish");
                if (menuTabBar != null) menuTabBar.setVisibility(View.GONE);
                if (btnSelect != null) btnSelect.setText("INSPECT");
                break;
            case "equipment":
                menuTitle.setText("INVENTORY");
                menuHint.setText("D-Pad: Browse Rods & Bait  •  Equip: Set Active");
                if (menuTabBar != null) menuTabBar.setVisibility(View.VISIBLE);
                if (btnTabPrev != null) btnTabPrev.setText("Rods");
                if (btnTabNext != null) btnTabNext.setText("Bait");
                if (btnSelect != null) btnSelect.setText("EQUIP");
                break;
            default:
                menuTitle.setText("MENU");
                menuHint.setText("D-Pad: Navigate  •  Select: Confirm");
                if (menuTabBar != null) menuTabBar.setVisibility(View.GONE);
                if (btnSelect != null) btnSelect.setText("SELECT");
                break;
        }
    }

    private void sendMenuAction(String action) {
        JSONObject msg = new JSONObject();
        try {
            msg.put("type", "menu");
            msg.put("action", action);
        } catch (JSONException e) {
            e.printStackTrace();
        }
        sendMessage(msg);
    }

    private void setupConnectionUI() {
        statusText = findViewById(R.id.statusText);
        connectionSubtext = findViewById(R.id.connectionSubtext);
        connectingSpinner = findViewById(R.id.connectingSpinner);
        playerNameInput = findViewById(R.id.playerNameInput);
        serverIpInput = findViewById(R.id.serverIpInput);
        connectButton = findViewById(R.id.connectButton);
        discoverButton = findViewById(R.id.discoverButton);
        Button btnToggleManual = findViewById(R.id.btnToggleManual);
        LinearLayout manualConnectSection = findViewById(R.id.manualConnectSection);

        if (playerNameInput != null) {
            playerNameInput.setText(getSavedPlayerName());
            playerNameInput.addTextChangedListener(new TextWatcher() {
                @Override
                public void beforeTextChanged(CharSequence s, int start, int count, int after) {}

                @Override
                public void onTextChanged(CharSequence s, int start, int before, int count) {}

                @Override
                public void afterTextChanged(Editable s) {
                    savePlayerName(s != null ? s.toString() : "");
                }
            });
        }

        String savedIp = getSavedIp();
        if (serverIpInput != null && savedIp != null && !savedIp.isEmpty()) {
            serverIpInput.setText(savedIp);
        }

        if (btnToggleManual != null && manualConnectSection != null) {
            btnToggleManual.setOnClickListener(v -> {
                boolean show = manualConnectSection.getVisibility() != View.VISIBLE;
                manualConnectSection.setVisibility(show ? View.VISIBLE : View.GONE);
                btnToggleManual.setText(show ? "Hide Manual Setup ▴" : "Manual IP Setup ▾");
            });
        }

        if (connectButton != null) {
            connectButton.setOnClickListener(v -> {
                String ip = serverIpInput != null ? serverIpInput.getText().toString().trim() : "";
                if (ip.isEmpty()) {
                    Toast.makeText(this, "Enter an IP address first", Toast.LENGTH_SHORT).show();
                    return;
                }
                handler.removeCallbacks(autoDiscoverRunnable);
                reconnectFailureCount = 0;
                connectToServer(ip);
            });
        }

        if (discoverButton != null) {
            discoverButton.setOnClickListener(v -> {
                triedSavedIpThisCycle = false;
                reconnectFailureCount = 0;
                startAutoDiscovery(true);
            });
        }

        if (wantConnected && lastIp != null && reconnectFailureCount <= 1) {
            setConnectionStatusUI("Reconnecting to " + lastIp + "...", "Hold tight — restoring link", true);
        } else if (isDiscovering) {
            setConnectionStatusUI("Searching for Tight Lines PC...", "Auto-connecting on the same Wi-Fi or Hotspot", true);
        } else {
            startAutoDiscovery(false);
        }
    }

    private void setConnectionStatusUI(String status, String subtext, boolean busy) {
        if (statusText != null) statusText.setText(status);
        if (connectionSubtext != null && subtext != null) connectionSubtext.setText(subtext);
        if (connectingSpinner != null) {
            connectingSpinner.setVisibility(busy ? View.VISIBLE : View.INVISIBLE);
        }
    }

    private String getSavedIp() {
        return getSharedPreferences("controller_prefs", MODE_PRIVATE).getString(PREF_LAST_IP, null);
    }

    private void saveLastIp(String ip) {
        if (ip == null || ip.isEmpty()) return;
        getSharedPreferences("controller_prefs", MODE_PRIVATE)
                .edit()
                .putString(PREF_LAST_IP, ip)
                .apply();
    }

    private String getSavedPlayerName() {
        String saved = getSharedPreferences("controller_prefs", MODE_PRIVATE).getString(PREF_PLAYER_NAME, "");
        return saved == null ? "" : saved.trim();
    }

    private void savePlayerName(String name) {
        String clean = name == null ? "" : name.trim();
        if (clean.length() > MAX_PLAYER_NAME_LENGTH) {
            clean = clean.substring(0, MAX_PLAYER_NAME_LENGTH);
        }
        getSharedPreferences("controller_prefs", MODE_PRIVATE)
                .edit()
                .putString(PREF_PLAYER_NAME, clean)
                .apply();
    }

    private String getCurrentScreenName() {
        if (currentState == null) return "connection";
        switch (currentState) {
            case OVERWORLD: return "overworld";
            case CASTING: return "casting";
            case REELING: return "reeling";
            case MENU: return "menu";
            case CONNECTION:
            default:
                return "connection";
        }
    }

    private void sendScreenState() {
        if (!isConnected) return;
        JSONObject msg = new JSONObject();
        try {
            msg.put("type", "screen_state");
            msg.put("screen", getCurrentScreenName());
            msg.put("active_menu", activeMenu);
        } catch (JSONException e) {
            e.printStackTrace();
        }
        sendMessage(msg);
    }

    private void updatePlayerIdentityBadge() {
        TextView badge = findViewById(R.id.playerIdentityBadge);
        if (badge == null) return;
        String name = assignedPlayerName == null ? "" : assignedPlayerName.trim();
        if ("left".equals(assignedScreenSide)) {
            badge.setVisibility(View.VISIBLE);
            badge.setText(name.isEmpty() ? "◀ LEFT SCREEN" : "◀ LEFT SCREEN  •  " + name);
            badge.setTextColor(Color.parseColor("#7CE8FF"));
        } else if ("right".equals(assignedScreenSide)) {
            badge.setVisibility(View.VISIBLE);
            badge.setText(name.isEmpty() ? "RIGHT SCREEN ▶" : name + "  •  RIGHT SCREEN ▶");
            badge.setTextColor(Color.parseColor("#FFB28A"));
        } else {
            badge.setVisibility(View.GONE);
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (gestureDetector != null) gestureDetector.onTouchEvent(event);
        return true;
    }

    private String getOrCreateDeviceId() {
        SharedPreferences prefs = getSharedPreferences("controller_prefs", MODE_PRIVATE);
        String existingId = prefs.getString("device_id", null);
        if (existingId != null) return existingId;

        String newId = UUID.randomUUID().toString();
        prefs.edit().putString("device_id", newId).apply();
        return newId;
    }

    private void connectToServer(String ip) {
        if (webSocket != null) {
            webSocket.close(1000, "Reconnecting");
            webSocket = null;
        }
        isConnected = false;
        lastIp = ip;
        wantConnected = true;
        handler.removeCallbacks(reconnectRunnable);
        handler.removeCallbacks(autoDiscoverRunnable);
        final int attempt = ++connectionAttempt;

        serverUrl = "ws://" + ip + ":" + SERVER_PORT;
        Request request = new Request.Builder().url(serverUrl).build();

        runOnUiThread(() -> setConnectionStatusUI(
                "Connecting to " + ip + "...",
                "Handshaking with Tight Lines PC",
                true
        ));

        webSocket = client.newWebSocket(request, new WebSocketListener() {
            @Override
            public void onOpen(WebSocket ws, Response response) {
                if (attempt != connectionAttempt) return;
                isConnected = true;
                reconnectFailureCount = 0;
                triedSavedIpThisCycle = false;
                saveLastIp(ip);
                handler.removeCallbacks(autoDiscoverRunnable);
                handler.removeCallbacks(reconnectRunnable);

                JSONObject msg = new JSONObject();
                try {
                    msg.put("type", "connected");
                    msg.put("device_id", deviceId);
                    msg.put("screen", "overworld");
                    String savedName = getSavedPlayerName();
                    if (!savedName.isEmpty()) {
                        msg.put("player_name", savedName);
                    }
                } catch (JSONException e) {
                    e.printStackTrace();
                }
                sendMessage(msg);
                switchToState(AppState.OVERWORLD);
            }

            @Override
            public void onMessage(WebSocket ws, ByteString bytes) {
                onMessage(ws, bytes.utf8());
            }

            @Override
            public void onMessage(WebSocket ws, String text) {
                if (attempt != connectionAttempt) return;
                try {
                    JSONObject json = new JSONObject(text);

                    if ("vibrate".equals(json.optString("type"))) {
                        if ("bite".equals(json.optString("reason"))) {
                            vibrateOnce(300);
                        } else {
                            vibratePattern(new long[]{0, 120, 80, 120});
                        }
                    }

                    if ("player_info".equals(json.optString("type"))) {
                        assignedPlayerName = json.optString("player_name", "").trim();
                        assignedScreenSide = json.optString("screen_side", "").trim().toLowerCase();
                        runOnUiThread(MainActivity.this::updatePlayerIdentityBadge);
                    }

                    if ("config".equals(json.optString("type")) || json.has("sensitivity") || json.has("swing_threshold") || json.has("tilt_filter_alpha")) {
                        if (json.has("sensitivity")) {
                            applySensitivity((float) json.getDouble("sensitivity"));
                        }
                        if (json.has("swing_threshold")) {
                            swingThreshold = (float) json.getDouble("swing_threshold");
                        }
                        if (json.has("tilt_filter_alpha")) {
                            tiltFilterAlpha = (float) json.getDouble("tilt_filter_alpha");
                        }
                    }

                    if (json.has("game_state")) {
                        String stateStr = json.getString("game_state");
                        switch (stateStr) {
                            case "overworld":
                                underlyingGameState = AppState.OVERWORLD;
                                break;
                            case "casting":
                                underlyingGameState = AppState.CASTING;
                                break;
                            case "reeling":
                                underlyingGameState = AppState.REELING;
                                activeMenu = "none";
                                break;
                        }
                        if (underlyingGameState == AppState.REELING || "none".equals(activeMenu)) {
                            switchToState(underlyingGameState);
                        }
                    }

                    if (json.has("active_menu")) {
                        activeMenu = json.optString("active_menu", "none");
                        if ("none".equals(activeMenu)) {
                            switchToState(underlyingGameState);
                        } else if (currentState != AppState.MENU) {
                            switchToState(AppState.MENU);
                        } else {
                            runOnUiThread(MainActivity.this::refreshMenuUI);
                            sendScreenState();
                        }
                    }
                } catch (JSONException e) {
                    e.printStackTrace();
                }
            }

            @Override
            public void onFailure(WebSocket ws, Throwable t, Response response) {
                if (attempt != connectionAttempt) return;
                handleConnectionLost();
            }

            @Override
            public void onClosed(WebSocket ws, int code, String reason) {
                if (attempt != connectionAttempt) return;
                handleConnectionLost();
            }
        });
    }

    private void handleConnectionLost() {
        isConnected = false;
        activeMenu = "none";
        assignedScreenSide = "";
        reconnectFailureCount++;
        switchToState(AppState.CONNECTION);
        if (wantConnected && lastIp != null && reconnectFailureCount <= 1) {
            scheduleReconnect();
        } else {
            wantConnected = false;
            runOnUiThread(() -> {
                if (currentState == AppState.CONNECTION && !isConnected) {
                    startAutoDiscovery(false);
                }
            });
        }
    }

    private List<InetAddress> getBroadcastAddresses() {
        List<InetAddress> addresses = new ArrayList<>();
        try {
            WifiManager wifiManager = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
            DhcpInfo dhcp = wifiManager.getDhcpInfo();
            if (dhcp != null && dhcp.ipAddress != 0 && dhcp.netmask != 0) {
                int broadcastInt = (dhcp.ipAddress & dhcp.netmask) | ~dhcp.netmask;
                byte[] quads = new byte[4];
                for (int k = 0; k < 4; k++) {
                    quads[k] = (byte) ((broadcastInt >> (k * 8)) & 0xFF);
                }
                addresses.add(InetAddress.getByAddress(quads));
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        try {
            addresses.add(InetAddress.getByName("255.255.255.255"));
        } catch (IOException e) {
            e.printStackTrace();
        }
        return addresses;
    }

    private void startAutoDiscovery(boolean userInitiated) {
        if (isConnected) return;
        handler.removeCallbacks(autoDiscoverRunnable);
        if (isDiscovering) return;
        performDiscovery(userInitiated);
    }

    private void performDiscovery(boolean userInitiated) {
        if (isDiscovering || isConnected) return;
        isDiscovering = true;

        runOnUiThread(() -> setConnectionStatusUI(
                "Searching for Tight Lines PC...",
                "Auto-connecting on the same Wi-Fi or Hotspot",
                true
        ));

        new Thread(() -> {
            try (DatagramSocket socket = new DatagramSocket()) {
                socket.setBroadcast(true);
                socket.setSoTimeout(DISCOVERY_TIMEOUT_MS);

                byte[] sendData = DISCOVERY_MESSAGE.getBytes();
                boolean anySent = false;
                IOException lastSendError = null;

                for (InetAddress addr : getBroadcastAddresses()) {
                    try {
                        DatagramPacket sendPacket = new DatagramPacket(sendData, sendData.length, addr, DISCOVERY_PORT);
                        socket.send(sendPacket);
                        anySent = true;
                    } catch (IOException sendError) {
                        lastSendError = sendError;
                    }
                }
                if (!anySent && lastSendError != null) throw lastSendError;

                byte[] receiveBuffer = new byte[256];
                DatagramPacket receivePacket = new DatagramPacket(receiveBuffer, receiveBuffer.length);
                socket.receive(receivePacket);

                String discoveredIp = receivePacket.getAddress().getHostAddress();
                if (discoveredIp == null || discoveredIp.isEmpty()) {
                    discoveredIp = new String(receivePacket.getData(), 0, receivePacket.getLength()).trim();
                }
                final String foundIp = discoveredIp;
                isDiscovering = false;

                runOnUiThread(() -> {
                    if (serverIpInput != null) serverIpInput.setText(foundIp);
                    setConnectionStatusUI("Found PC at " + foundIp, "Connecting automatically...", true);
                    connectToServer(foundIp);
                });

            } catch (SocketTimeoutException e) {
                isDiscovering = false;
                runOnUiThread(() -> onDiscoveryMissed(userInitiated, "Make sure Tight Lines is running on your PC"));
            } catch (IOException e) {
                isDiscovering = false;
                runOnUiThread(() -> onDiscoveryMissed(userInitiated, "Check Wi-Fi or Hotspot connection"));
            }
        }).start();
    }

    private void onDiscoveryMissed(boolean userInitiated, String hint) {
        if (isConnected || currentState != AppState.CONNECTION) return;

        String savedIp = getSavedIp();
        if (!triedSavedIpThisCycle && savedIp != null && !savedIp.isEmpty()) {
            triedSavedIpThisCycle = true;
            setConnectionStatusUI("Trying last PC (" + savedIp + ")...", hint, true);
            connectToServer(savedIp);
            return;
        }

        triedSavedIpThisCycle = false;
        setConnectionStatusUI("Searching for Tight Lines PC...", hint + " • Retrying automatically", true);
        if (userInitiated) {
            Toast.makeText(this, "No PC found yet — still scanning", Toast.LENGTH_SHORT).show();
        }
        handler.removeCallbacks(autoDiscoverRunnable);
        handler.postDelayed(autoDiscoverRunnable, AUTO_DISCOVER_INTERVAL_MS);
    }

    @SuppressWarnings("deprecation")
    private void vibrateOnce(long ms) {
        Vibrator v = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
        if (v == null || !v.hasVibrator()) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE));
        } else {
            v.vibrate(ms);
        }
    }

    @SuppressWarnings("deprecation")
    private void vibratePattern(long[] pattern) {
        Vibrator v = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
        if (v == null || !v.hasVibrator()) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createWaveform(pattern, -1));
        } else {
            v.vibrate(pattern, -1);
        }
    }

    private void scheduleReconnect() {
        if (!wantConnected || lastIp == null) return;
        handler.removeCallbacks(reconnectRunnable);
        handler.postDelayed(reconnectRunnable, RECONNECT_DELAY_MS);
    }

    private void sendMessage(JSONObject json) {
        if (webSocket != null) webSocket.send(json.toString());
    }

    public String getConnectionStatus() {
        return isConnected ? "Connected" : "Not connected";
    }

    private class GestureListener extends GestureDetector.SimpleOnGestureListener {
        @Override
        public boolean onDown(MotionEvent e) {
            return true;
        }

        @Override
        public boolean onSingleTapUp(MotionEvent e) {
            JSONObject msg = new JSONObject();
            try {
                msg.put("type", "cancel");
            } catch (JSONException ex) {
                ex.printStackTrace();
            }
            sendMessage(msg);
            return true;
        }

        @Override
        public boolean onFling(MotionEvent e1, MotionEvent e2, float velocityX, float velocityY) {
            if (e1 == null) return false;

            float dx = e2.getX() - e1.getX();
            float dy = e2.getY() - e1.getY();

            String direction = (Math.abs(dx) > Math.abs(dy)) ? ((dx > 0) ? "right" : "left") : ((dy > 0) ? "down" : "up");

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

    public void applySensitivity(float sens) {
        float clamped = Math.max(0.0f, Math.min(1.0f, sens));
        // High sensitivity (1.0) -> swingThreshold 12.0f, tiltFilterAlpha 0.70f (more responsive)
        // Low sensitivity (0.0) -> swingThreshold 16.0f, tiltFilterAlpha 0.95f (heavy smoothing, harder swing)
        swingThreshold = 16.0f - clamped * (16.0f - 12.0f);
        tiltFilterAlpha = 0.95f - clamped * (0.95f - 0.70f);
    }

    @Override
    public void onSensorChanged(SensorEvent event) {
        int sensorType = event.sensor.getType();
        if (sensorType == Sensor.TYPE_ACCELEROMETER) {
            handleAccelerometer(event);
            return;
        }
        if (sensorType != Sensor.TYPE_GYROSCOPE) return;

        float x = event.values[0];
        float y = event.values[1];
        float z = event.values[2];
        double magnitude = Math.sqrt(x * x + y * y + z * z);

        long now = System.currentTimeMillis();

        if (swingWindowOpen) {
            if (magnitude > swingPeak) swingPeak = magnitude;
            if (now - swingWindowStartMs >= SWING_PEAK_WINDOW_MS) {
                swingWindowOpen = false;
                lastSwingTimeMs = now;
                sendSwing(swingPeak);
            }
            return;
        }

        if (magnitude < swingThreshold) return;
        if (now - lastSwingTimeMs < SWING_COOLDOWN_MS) return;

        swingWindowOpen = true;
        swingWindowStartMs = now;
        swingPeak = magnitude;
    }

    private void sendSwing(double magnitude) {
        JSONObject msg = new JSONObject();
        try {
            msg.put("type", "swing");
            msg.put("magnitude", magnitude);
        } catch (JSONException ex) {
            ex.printStackTrace();
        }
        sendMessage(msg);
    }

    @SuppressWarnings("deprecation")
    private void handleAccelerometer(SensorEvent event) {
        long nowMs = System.currentTimeMillis();
        boolean swingBusy = swingWindowOpen || (nowMs - lastSwingTimeMs < TILT_HOLD_AFTER_SWING_MS);

        if (!gravityInitialized) {
            System.arraycopy(event.values, 0, gravity, 0, 3);
            gravityInitialized = true;
        } else if (!swingBusy) {
            for (int i = 0; i < 3; i++) {
                gravity[i] = tiltFilterAlpha * gravity[i] + (1f - tiltFilterAlpha) * event.values[i];
            }
        }

        long now = System.currentTimeMillis();
        if (!isConnected || now - lastTiltSentMs < TILT_SEND_INTERVAL_MS) return;
        lastTiltSentMs = now;

        float screenRight;
        switch (getWindowManager().getDefaultDisplay().getRotation()) {
            case Surface.ROTATION_90:
                screenRight = -gravity[1];
                break;
            case Surface.ROTATION_180:
                screenRight = -gravity[0];
                break;
            case Surface.ROTATION_270:
                screenRight = gravity[1];
                break;
            default:
                screenRight = gravity[0];
                break;
        }
        if (currentState == AppState.REELING) return;

        float maxSin = (float) Math.sin(Math.toRadians(TILT_FULL_ANGLE_DEG));
        double ratio = -screenRight / (SensorManager.GRAVITY_EARTH * maxSin);
        double value = Math.max(-1.0, Math.min(1.0, ratio));

        JSONObject msg = new JSONObject();
        try {
            msg.put("type", "tilt");
            msg.put("value", value);
        } catch (JSONException ex) {
            ex.printStackTrace();
        }
        sendMessage(msg);
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int accuracy) {}

    @Override
    protected void onResume() {
        super.onResume();
        if (gyroSensor != null) sensorManager.registerListener(this, gyroSensor, SensorManager.SENSOR_DELAY_GAME);
        if (accelSensor != null) sensorManager.registerListener(this, accelSensor, SensorManager.SENSOR_DELAY_GAME);
        if (currentState == AppState.CONNECTION && !isConnected) {
            startAutoDiscovery(false);
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        sensorManager.unregisterListener(this);
        swingWindowOpen = false;
        handler.removeCallbacks(autoDiscoverRunnable);
        handler.removeCallbacks(reconnectRunnable);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        wantConnected = false;
        handler.removeCallbacks(autoDiscoverRunnable);
        handler.removeCallbacks(reconnectRunnable);
        if (webSocket != null) webSocket.close(1000, "App closed");
    }
}