package com.example.free_play

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Display
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : AudioServiceActivity() {

    private val PERM_CHANNEL  = "com.example.free_play/permissions"
    private val CLOCK_CHANNEL = "com.example.free_play/clock"
    private val SCREEN_CHANNEL = "aura_player/screen_state"
    private val AOD_CHANNEL = "aura_player/always_on_display"
    private val STORAGE_REQUEST_CODE = 1001
    private val mainHandler = Handler(Looper.getMainLooper())

    private var pendingResult: MethodChannel.Result? = null
    private var screenReceiver: BroadcastReceiver? = null
    private var displayListener: DisplayManager.DisplayListener? = null
    private var isScreenListenerRegistered = false

    // UDP clock-sync server (host side)
    private var udpServerSocket: DatagramSocket? = null
    private val serverRunning = AtomicBoolean(false)
    private var serverThread: Thread? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Storage permission channel ────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkStoragePermission"   -> result.success(hasStoragePermission())
                    "requestStoragePermission" -> {
                        if (hasStoragePermission()) {
                            result.success(true)
                        } else {
                            pendingResult = result
                            requestStoragePermission()
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Clock-sync channel ────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLOCK_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // Returns current device monotonic time in microseconds
                    "nowMicros" -> result.success(System.nanoTime() / 1000L)

                    // HOST: start UDP echo server on given port
                    "startUdpServer" -> {
                        val port = call.argument<Int>("port") ?: 47474
                        startUdpServer(port, result)
                    }

                    // HOST: stop UDP server
                    "stopUdpServer" -> {
                        stopUdpServer()
                        result.success(null)
                    }

                    // HOST: get own LAN IP address
                    "getLocalIp" -> result.success(getLocalIpAddress())

                    // GUEST: measure RTT + clock offset to host
                    // Returns map: {offsetMicros: int, rttMicros: int}
                    "measureClockOffset" -> {
                        val host    = call.argument<String>("host") ?: ""
                        val port    = call.argument<Int>("port") ?: 47474
                        val samples = call.argument<Int>("samples") ?: 8
                        Thread {
                            try {
                                val r = measureClockOffset(host, port, samples)
                                mainHandler.post { result.success(r) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("CLOCK_ERROR", e.message, null)
                                }
                            }
                        }.start()
                    }

                    else -> result.notImplemented()
                }
            }

        val screenChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL)
        screenChannel.setMethodCallHandler { call, result ->
            if (call.method == "registerScreenStateListener") {
                registerScreenListeners(screenChannel, flutterEngine)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        val aodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AOD_CHANNEL)
        aodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isAlwaysOnDisplaySupported" -> result.success(true)
                "enableAODOptimizations", "enableMusicControlsOnAOD", "disableMusicControlsOnAOD",
                "updateMusicInfo", "setCustomAODLayout", "enableBeatResponse",
                "setAODBrightness", "setAODRefreshRate", "keepAlive" -> result.success(true)
                else -> result.notImplemented()
            }
        }
    }

    private fun registerScreenListeners(screenChannel: MethodChannel, flutterEngine: FlutterEngine) {
        if (isScreenListenerRegistered) return
        val aodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AOD_CHANNEL)

        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent == null) return
                val isScreenOn = when (intent.action) {
                    Intent.ACTION_SCREEN_ON -> true
                    Intent.ACTION_SCREEN_OFF -> false
                    else -> return
                }
                mainHandler.post {
                    val args = HashMap<String, Any>()
                    args["isScreenOn"] = isScreenOn
                    screenChannel.invokeMethod("onScreenStateChanged", args)
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        registerReceiver(screenReceiver, filter)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
            val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
            displayListener = object : DisplayManager.DisplayListener {
                override fun onDisplayAdded(displayId: Int) {}
                override fun onDisplayRemoved(displayId: Int) {}
                override fun onDisplayChanged(displayId: Int) {
                    if (displayId == Display.DEFAULT_DISPLAY) {
                        val display = displayManager.getDisplay(displayId) ?: return
                        val state = display.state
                        val isAODActive = (state == Display.STATE_DOZE || state == Display.STATE_DOZE_SUSPEND)
                        mainHandler.post {
                            val screenArgs = HashMap<String, Any>()
                            screenArgs["isScreenOn"] = (state == Display.STATE_ON || state == Display.STATE_VR)
                            screenArgs["isAODActive"] = isAODActive
                            screenChannel.invokeMethod("onAODStateChanged", screenArgs)

                            val aodArgs = HashMap<String, Any>()
                            aodArgs["isActive"] = isAODActive
                            aodChannel.invokeMethod("onAODStatusChanged", aodArgs)
                        }
                    }
                }
            }
            displayManager.registerDisplayListener(displayListener, mainHandler)
        }

        isScreenListenerRegistered = true
    }

    // ── UDP Echo Server (host) ────────────────────────────────────────────────
    // Protocol: guest sends 8-byte little-endian int64 (t1 micros)
    //           host echoes back 16 bytes: t1 (8 bytes) + t2 (8 bytes)

    private fun startUdpServer(port: Int, result: MethodChannel.Result) {
        stopUdpServer()
        try {
            val socket = DatagramSocket(port)
            udpServerSocket = socket
            serverRunning.set(true)
            serverThread = Thread {
                val buf = ByteArray(8)
                val packet = DatagramPacket(buf, buf.size)
                while (serverRunning.get()) {
                    try {
                        socket.receive(packet)
                        val t2 = System.nanoTime() / 1000L
                        val reply = ByteArray(16)
                        System.arraycopy(packet.data, 0, reply, 0, 8)
                        writeLong(reply, 8, t2)
                        socket.send(DatagramPacket(reply, 16, packet.address, packet.port))
                    } catch (_: Exception) { /* socket closed */ }
                }
            }.also { it.isDaemon = true; it.start() }
            result.success(port)
        } catch (e: Exception) {
            result.error("UDP_ERROR", e.message, null)
        }
    }

    private fun stopUdpServer() {
        serverRunning.set(false)
        udpServerSocket?.close()
        udpServerSocket = null
        serverThread?.interrupt()
        serverThread = null
    }

    // ── Clock offset measurement (guest) ─────────────────────────────────────
    // NTP-style: sends N probes, discards outliers, returns median offset
    // offset = how many microseconds the host clock is AHEAD of guest clock

    private fun measureClockOffset(host: String, port: Int, samples: Int): Map<String, Long> {
        val socket = DatagramSocket()
        socket.soTimeout = 2000
        val addr = InetAddress.getByName(host)

        val offsets = mutableListOf<Long>()
        val rtts    = mutableListOf<Long>()

        repeat(samples) {
            try {
                val t1 = System.nanoTime() / 1000L
                val sendBuf = ByteArray(8)
                writeLong(sendBuf, 0, t1)
                socket.send(DatagramPacket(sendBuf, 8, addr, port))

                val recvBuf = ByteArray(16)
                val recvPacket = DatagramPacket(recvBuf, 16)
                socket.receive(recvPacket)
                val t4 = System.nanoTime() / 1000L

                val t1Echo = readLong(recvBuf, 0)
                val t2     = readLong(recvBuf, 8)

                if (t1Echo == t1) {
                    val rtt    = t4 - t1
                    // offset: how far ahead host clock is relative to guest
                    val offset = t2 - t1 - rtt / 2
                    offsets.add(offset)
                    rtts.add(rtt)
                }
                Thread.sleep(15)
            } catch (_: Exception) {}
        }

        socket.close()
        if (offsets.isEmpty()) throw Exception("No responses from host UDP server")

        offsets.sort()
        rtts.sort()
        return mapOf(
            "offsetMicros" to offsets[offsets.size / 2],
            "rttMicros"    to rtts[rtts.size / 2]
        )
    }

    // ── Byte helpers (little-endian int64) ───────────────────────────────────

    private fun writeLong(buf: ByteArray, offset: Int, value: Long) {
        for (i in 0..7) buf[offset + i] = ((value ushr (i * 8)) and 0xFF).toByte()
    }

    private fun readLong(buf: ByteArray, offset: Int): Long {
        var v = 0L
        for (i in 0..7) v = v or ((buf[offset + i].toLong() and 0xFF) shl (i * 8))
        return v
    }

    // ── LAN IP ───────────────────────────────────────────────────────────────

    private fun getLocalIpAddress(): String {
        try {
            val interfaces = java.net.NetworkInterface.getNetworkInterfaces()
            for (intf in interfaces) {
                if (!intf.isUp || intf.isLoopback) continue
                for (addr in intf.inetAddresses) {
                    if (!addr.isLoopbackAddress && addr is java.net.Inet4Address) {
                        return addr.hostAddress ?: ""
                    }
                }
            }
        } catch (_: Exception) {}
        return ""
    }

    // ── Storage permission ────────────────────────────────────────────────────

    private fun hasStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.READ_MEDIA_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestStoragePermission() {
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        ActivityCompat.requestPermissions(this, arrayOf(permission), STORAGE_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == STORAGE_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingResult?.success(granted)
            pendingResult = null
        }
    }

    override fun onDestroy() {
        stopUdpServer()
        if (isScreenListenerRegistered) {
            screenReceiver?.let {
                try { unregisterReceiver(it) } catch (_: Exception) {}
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
                displayListener?.let {
                    val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
                    displayManager.unregisterDisplayListener(it)
                }
            }
            isScreenListenerRegistered = false
        }
        super.onDestroy()
    }
}
