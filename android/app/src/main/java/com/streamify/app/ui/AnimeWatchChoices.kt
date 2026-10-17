package com.streamify.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.streamify.app.data.*

@Composable
fun AnimeWatchChoices(store: LocalStore, watch: () -> Unit) {
    var selected by remember { mutableStateOf(store.animeServerId) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            listOf("sub", "dub").forEach { language ->
                Box(Modifier.weight(1f)) {
                    var expanded by remember { mutableStateOf(false) }
                    SecondaryButton(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) {
                        Text("Watch $language"); Spacer(Modifier.width(6.dp)); Icon(Icons.Rounded.ExpandMore, null)
                    }
                    DropdownMenu(expanded, { expanded = false }) {
                        animeServers.filter { it.id.endsWith("-$language") }.forEach { provider ->
                            DropdownMenuItem(text = { Text(provider.label) }, onClick = {
                                store.animeServerId = provider.id; selected = provider.id; expanded = false; watch()
                            })
                        }
                    }
                }
            }
        }
        Text("Watch uses ${animeServers.first { it.id == selected }.label}. Availability varies by episode. Preferences and anime history are saved on this device.",
            color = Muted, style = MaterialTheme.typography.bodySmall)
    }
}
