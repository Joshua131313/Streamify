package com.streamify.app.data

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Application-scoped observation of usable internet, including airplane/captive-portal states. */
class NetworkStatus private constructor(context: Context) {
    private val manager = context.getSystemService(ConnectivityManager::class.java)
    private fun connected(): Boolean = manager.getNetworkCapabilities(manager.activeNetwork)?.let {
        it.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) && it.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    } == true
    private val state = MutableStateFlow(connected())
    val online = state.asStateFlow()
    init {
        manager.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { state.value=connected() }
            override fun onLost(network: Network) { state.value=connected() }
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) { state.value=connected() }
        })
    }
    companion object {
        @Volatile private var instance: NetworkStatus? = null
        fun get(context: Context) = instance ?: synchronized(this) { instance ?: NetworkStatus(context.applicationContext).also { instance=it } }
    }
}
