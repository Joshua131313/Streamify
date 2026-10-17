package com.streamify.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.unit.dp
import com.streamify.app.data.Media
import com.streamify.app.data.MediaType
import com.streamify.app.downloads.DownloadButton

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MediaActionsSheet(media:Media, dismiss:()->Unit, info:()->Unit, season:Int=1, episode:Int=1, remove:(()->Unit)?=null) {
    ModalBottomSheet(onDismissRequest=dismiss,containerColor=Panel) {
        Column(Modifier.fillMaxWidth().padding(horizontal=24.dp).padding(bottom=28.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment=Alignment.CenterVertically) {
                Text(media.title,Modifier.weight(1f),style=MaterialTheme.typography.headlineSmall)
                IconButton(onClick=dismiss) {Icon(Icons.Rounded.Close,"Close actions")}
            }
            TextButton(onClick={dismiss();info()},modifier=Modifier.fillMaxWidth().heightIn(min=52.dp),colors=ButtonDefaults.textButtonColors(contentColor=MaterialTheme.colorScheme.onSurface)) {
                Icon(Icons.Rounded.Info,null);Spacer(Modifier.width(16.dp));Text("More info",Modifier.weight(1f))
            }
            if(media.type!=MediaType.ANIME) DownloadButton(media,if(media.type==MediaType.TV) season.coerceAtLeast(1) else 0,if(media.type==MediaType.TV) episode.coerceAtLeast(1) else 0)
            remove?.let { action ->
                TextButton(onClick={dismiss();action()},modifier=Modifier.fillMaxWidth().heightIn(min=52.dp),colors=ButtonDefaults.textButtonColors(contentColor=MaterialTheme.colorScheme.onSurface)) {
                    Icon(Icons.Rounded.Close,null);Spacer(Modifier.width(16.dp));Text("Remove from row",Modifier.weight(1f))
                }
            }
        }
    }
}
