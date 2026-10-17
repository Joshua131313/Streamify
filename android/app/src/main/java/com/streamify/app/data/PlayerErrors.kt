package com.streamify.app.data

/** WebView error codes are stable across Android versions. */
fun playerLoadError(code: Int): String = when (code) {
    -2 -> "The stream provider’s address could not be found. It may be unavailable or blocked by your network. Retry later or try another network."
    -6 -> "Could not connect to the stream provider. Check your connection or choose another source."
    -8 -> "The stream provider took too long to respond. Retry or choose another source."
    -11 -> "The stream provider’s secure connection failed. Choose another source or try again later."
    else -> "This source could not load. Retry, switch source, or open in browser."
}
