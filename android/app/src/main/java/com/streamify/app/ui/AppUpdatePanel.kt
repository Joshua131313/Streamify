package com.streamify.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.SystemUpdate
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.material.icons.rounded.Close
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

@Composable
fun HomeUpdateNotice(update:UpdateViewModel) {
    val release=update.available ?: return
    var dismissed by rememberSaveable {mutableLongStateOf(0L)}
    if(dismissed==release.versionCode) return
    val context=LocalContext.current
    PagePanel(Modifier.padding(horizontal=20.dp)) {
        Row(verticalAlignment=Alignment.CenterVertically) {
            Icon(Icons.Rounded.SystemUpdate,null,Modifier.size(24.dp))
            Column(Modifier.weight(1f).padding(horizontal=12.dp)) {
                Text("A new Streamify update is ready",style=MaterialTheme.typography.titleSmall)
                Text("Version ${release.versionName}",color=Muted,style=MaterialTheme.typography.bodySmall)
            }
            IconButton(onClick={dismissed=release.versionCode}) {Icon(Icons.Rounded.Close,"Dismiss update notice")}
        }
        if(update.busy) {
            LinearProgressIndicator(progress={update.progress},modifier=Modifier.fillMaxWidth(),gapSize=0.dp)
            Text(update.message,color=Muted,style=MaterialTheme.typography.bodySmall)
        } else if(update.ready!=null) Text("Downloaded and verified. Ready to install.",color=Muted,style=MaterialTheme.typography.bodySmall)
        else Text(update.message,color=Muted,style=MaterialTheme.typography.bodySmall)
        Button(colors=ButtonDefaults.buttonColors(containerColor=androidx.compose.ui.graphics.Color.White,contentColor=androidx.compose.ui.graphics.Color.Black),onClick={if(update.ready!=null) update.install(context) else update.download()},enabled=!update.busy,modifier=Modifier.fillMaxWidth()) {
            Text(if(update.ready!=null) "Install update" else if(update.busy) "Downloading…" else "Download update")
        }
    }
}
