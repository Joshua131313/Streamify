package com.streamify.app.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.Image
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.streamify.app.R

@Composable
fun AppHeader(title: String, search: () -> Unit, library: () -> Unit, account: () -> Unit, settings: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().height(60.dp).padding(start = 16.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Image(painterResource(R.drawable.streamify_logo), "Streamify", Modifier.size(30.dp))
        Text(title, Modifier.weight(1f).padding(start = 10.dp), fontSize = 24.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        IconButton(onClick = search, modifier = Modifier.size(44.dp)) { Icon(Icons.Outlined.Search, "Search", Modifier.size(25.dp)) }
        IconButton(onClick = library, modifier = Modifier.size(44.dp)) { Icon(Icons.Outlined.Bookmarks, "My list", Modifier.size(23.dp)) }
        Box {
            IconButton(onClick = { menu = true }, modifier = Modifier.size(44.dp)) { Icon(Icons.Rounded.MoreVert, "More options", Modifier.size(25.dp)) }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("Account") }, leadingIcon = { Icon(Icons.Outlined.PersonOutline, null) }, onClick = { menu = false; account() })
                DropdownMenuItem(text = { Text("Settings") }, leadingIcon = { Icon(Icons.Outlined.Settings, null) }, onClick = { menu = false; settings() })
            }
        }
    }
}

/** Floating translucent navigation; root page feeds continue underneath it. */
@Composable
fun StreamifyBottomBar(selected: String, modifier: Modifier = Modifier, select: (String) -> Unit) {
    val haptics = androidx.compose.ui.platform.LocalHapticFeedback.current
    val tabs = listOf(
        Triple("Home", "Home", Icons.Outlined.Home),
        Triple("Sports", "Sports", Icons.Outlined.SportsBasketball),
        Triple("Browse", "Search", Icons.Outlined.Search),
        Triple("Library", "My list", Icons.Outlined.PersonOutline)
    )
    val dark = Canvas.luminance() < .5f
    val foreground = MaterialTheme.colorScheme.onSurface
    Box(modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.navigationBars.only(WindowInsetsSides.Bottom)).padding(horizontal = 24.dp, vertical = 10.dp), contentAlignment = Alignment.Center) {
        Surface(Modifier.widthIn(max = 460.dp).fillMaxWidth(), shape = RoundedCornerShape(28.dp),
            color = if (dark) Color(0xFF242328).copy(alpha = .9f) else Color(0xFFF3F0F6).copy(alpha = .94f),
            border = BorderStroke(.7.dp, foreground.copy(alpha = .16f)), shadowElevation = 16.dp, tonalElevation = 0.dp) {
            Row(Modifier.background(Brush.verticalGradient(listOf(Color.White.copy(alpha = .08f), Color.Transparent)))
                .selectableGroup().padding(5.dp)) {
                tabs.forEach { (name, label, icon) ->
                    val active = selected == name
                    val tint by animateColorAsState(if (active) foreground else foreground.copy(alpha = .5f), label = "Navigation color")
                    Column(Modifier.weight(1f).height(56.dp).clip(RoundedCornerShape(22.dp))
                        .background(if (active) foreground.copy(alpha = .06f) else Color.Transparent)
                        .selectable(active, role = Role.Tab, onClick = { if (!active) haptics.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.TextHandleMove); select(name) }),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                        if (name == "Library") Box(Modifier.size(24.dp).clip(RoundedCornerShape(7.dp)).background(StreamRed), contentAlignment = Alignment.Center) {
                            Icon(Icons.Rounded.Person, null, Modifier.size(18.dp), tint = Color.White)
                        } else Icon(icon, null, Modifier.size(24.dp), tint = tint)
                        Spacer(Modifier.height(4.dp))
                        Text(label, color = tint, fontSize = 10.sp, lineHeight = 12.sp,
                            fontWeight = if (active) FontWeight.SemiBold else FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}
