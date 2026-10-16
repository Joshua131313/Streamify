package com.streamify.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.SystemUpdate
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.streamify.app.*

@Composable
fun AppUpdatePanel() {
    val update: UpdateViewModel = androidx.lifecycle.viewmodel.compose.viewModel()
    val context = LocalContext.current
    PagePanel(Modifier.padding(horizontal = 20.dp)) {
        SectionLabel("App updates", "Installed ${BuildConfig.VERSION_NAME}")
        Text(update.message, color = Muted, style = MaterialTheme.typography.bodyMedium)
        update.available?.notes?.takeIf { it.isNotBlank() }?.let { Text(it.take(2000), style = MaterialTheme.typography.bodySmall) }
        if (update.busy) Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            if (update.progress > 0f) Text("${(update.progress * 100).toInt()}%")
        }
        SecondaryButton(onClick = { when { update.ready != null -> update.install(context); update.available != null -> update.download(); else -> update.check() } }, enabled = !update.busy, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Rounded.SystemUpdate, null); Spacer(Modifier.width(8.dp))
            Text(when { update.ready != null -> "Install update"; update.available != null -> "Download update"; else -> "Check for updates" })
        }
    }
}
