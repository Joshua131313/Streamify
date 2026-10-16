package com.streamify.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.material.icons.rounded.Reply
import androidx.compose.material.icons.rounded.AddReaction
import androidx.compose.material.icons.rounded.Close
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.rounded.ChatBubbleOutline
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.streamify.app.Destination
import com.streamify.app.StreamifyViewModel
import com.streamify.app.data.*
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlin.coroutines.coroutineContext

@Composable
fun LiveChat(game: Game, vm: StreamifyViewModel) {
    LiveChatRoom(chatRoomId(game), vm.accounts) { vm.navigate(Destination.Account) }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun LiveChatRoom(room: String, accounts: AccountRepository, onSignIn: () -> Unit) {
    val account by accounts.account.collectAsState()
    var user by remember { mutableStateOf(accounts.auth.currentUser?.uid) }
    DisposableEffect(accounts.auth) {
        val listener = com.google.firebase.auth.FirebaseAuth.AuthStateListener { user = it.currentUser?.uid }
        accounts.auth.addAuthStateListener(listener)
        onDispose { accounts.auth.removeAuthStateListener(listener) }
    }
    val repo = remember(accounts) { LiveChatRepository(accounts.auth, accounts.db) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val scope = rememberCoroutineScope()
    var state by remember(room) { mutableStateOf(ChatState()) }
    var retry by remember { mutableIntStateOf(0) }
    var message by remember(room) { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var reply by remember(room) { mutableStateOf<ChatMessage?>(null) }
    val scroll = rememberScrollState()
    LaunchedEffect(room, user, retry, lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { repo.messages(room).collect { state = it } }
    }
    LaunchedEffect(state.messages.lastOrNull()?.id) { scroll.animateScrollTo(scroll.maxValue) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Surface(shape = CircleShape, color = Panel) {
                Icon(Icons.Rounded.ChatBubbleOutline, null, Modifier.padding(12.dp).size(20.dp), tint = Muted)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("Game chat", style = MaterialTheme.typography.titleLarge)
                Text("Join the conversation", color = Muted, style = MaterialTheme.typography.bodySmall)
            }
            if (account.uid == null) SecondaryButton(onClick = onSignIn,
                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.onSurface)) { Text("Sign in") }
        }
        if (account.uid == null) Text("Chat as a guest. Sign in to use your profile name.", color = Muted, style = MaterialTheme.typography.bodySmall)
        if (state.loading) Box(Modifier.fillMaxWidth().height(64.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(Modifier.size(22.dp), color = Muted, strokeWidth = 2.dp)
        }
        state.error?.let { ErrorBanner(it) { retry++ } }
        Surface(shape = RoundedCornerShape(20.dp), color = Panel.copy(alpha = .45f), border = BorderStroke(1.dp, Muted.copy(alpha = .12f))) {
        Column(Modifier.fillMaxWidth().heightIn(min = 140.dp, max = 340.dp).verticalScroll(scroll).padding(12.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            state.messages.forEach { item ->
                val own = item.uid == user
                Row(Modifier.fillMaxWidth(), horizontalArrangement = if (own) Arrangement.End else Arrangement.Start) {
                    Surface(Modifier.widthIn(max = 300.dp), shape = RoundedCornerShape(18.dp, 18.dp, if (own) 5.dp else 18.dp, if (own) 18.dp else 5.dp),
                        color = if (own) MaterialTheme.colorScheme.onSurface.copy(alpha = .10f) else Panel) {
                        Column(Modifier.padding(horizontal = 14.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(if (own) "You" else item.sender, Modifier.weight(1f).clickable { message = message.trimEnd() + " @${item.handle()} " }, style = MaterialTheme.typography.labelSmall, color = Muted)
                                if (item.sentAt > 0) Text(java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date(item.sentAt)), style = MaterialTheme.typography.labelSmall, color = Muted)
                            }
                            item.reply?.let { quote -> Surface(color = Color.White.copy(alpha = .05f), shape = RoundedCornerShape(8.dp)) {
                                Column(Modifier.fillMaxWidth().padding(8.dp)) {
                                    Text("Reply to ${quote.sender}", style = MaterialTheme.typography.labelSmall, color = Muted)
                                    Text(quote.message, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall)
                                }
                            } }
                            Text(buildAnnotatedString {
                                append(item.message)
                                Regex("@[A-Za-z0-9_]+").findAll(item.message).forEach { match -> addStyle(SpanStyle(color = Color(0xFFA9C9FF), fontWeight = FontWeight.SemiBold), match.range.first, match.range.last + 1) }
                            }, style = MaterialTheme.typography.bodyMedium)
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                var choosing by remember(item.id) { mutableStateOf(false) }
                                Box {
                                    IconButton(onClick = { choosing = true }, modifier = Modifier.size(36.dp)) { Icon(Icons.Rounded.AddReaction, "React to message", Modifier.size(18.dp), tint = Muted) }
                                    DropdownMenu(choosing, { choosing = false }) { chatReactions.forEach { emoji -> DropdownMenuItem(text = { Text(emoji) }, onClick = {
                                        choosing = false
                                        scope.launch { try { repo.react(room, item.id, emoji) } catch (failure: Exception) { coroutineContext.ensureActive(); error = failure.localizedMessage } }
                                    }) } }
                                }
                                IconButton(onClick = { reply = item }, modifier = Modifier.size(36.dp)) { Icon(Icons.Rounded.Reply, "Reply to message", Modifier.size(18.dp), tint = Muted) }
                                item.votes.values.groupingBy { it }.eachCount().forEach { (emoji, count) ->
                                    Surface(shape = RoundedCornerShape(12.dp), color = if (item.votes[user] == emoji) Color.White.copy(alpha = .18f) else Color.White.copy(alpha = .05f), onClick = {
                                        scope.launch { try { repo.react(room, item.id, emoji) } catch (failure: Exception) { coroutineContext.ensureActive(); error = failure.localizedMessage } }
                                    }) { Text("$emoji $count", Modifier.padding(horizontal = 6.dp, vertical = 8.dp), style = MaterialTheme.typography.labelSmall) }
                                }
                            }
                        }
                    }
                }
            }
            if (!state.loading && state.error == null && state.messages.isEmpty()) {
                Column(Modifier.fillMaxWidth().padding(vertical = 28.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Be the first to say hello", style = MaterialTheme.typography.titleSmall)
                    Text("Share the moment with other fans.", color = Muted, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
        }
        Surface(shape = RoundedCornerShape(20.dp), color = Panel.copy(alpha = .65f), border = BorderStroke(1.dp, Muted.copy(alpha = .12f))) {
        Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        reply?.let { quoted -> Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).padding(start = 8.dp)) {
                Text("Replying to ${quoted.sender}", style = MaterialTheme.typography.labelSmall, color = Muted)
                Text(quoted.message, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall)
            }
            IconButton(onClick = { reply = null }) { Icon(Icons.Rounded.Close, "Cancel reply", Modifier.size(18.dp)) }
        } }
        val mention = Regex("(?:^|\\s)@([A-Za-z0-9_]*)$").find(message)
        if (mention != null) {
            state.messages.distinctBy { it.uid }.filter { it.handle().startsWith(mention.groupValues[1], ignoreCase = true) }.take(4).forEach { person ->
                Text("@${person.handle()}", Modifier.fillMaxWidth().clickable { message = message.substring(0, message.lastIndexOf('@')) + "@${person.handle()} " }.padding(10.dp), style = MaterialTheme.typography.bodySmall, color = Color(0xFFA9C9FF))
            }
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedTextField(message, { message = it.take(1000) }, placeholder = { Text("Say something…") },
                modifier = Modifier.weight(1f), shape = RoundedCornerShape(24.dp), maxLines = 4, enabled = !sending,
                colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = Muted.copy(alpha = .5f), unfocusedBorderColor = Color.Transparent,
                    focusedContainerColor = Panel, unfocusedContainerColor = Panel, cursorColor = MaterialTheme.colorScheme.onSurface))
            FilledIconButton(onClick = { if (!sending) { sending = true; error = null; scope.launch {
                try { repo.send(room, message, reply); message = ""; reply = null }
                catch (failure: Exception) { coroutineContext.ensureActive(); error = failure.localizedMessage }
                finally { sending = false }
            } } }, modifier = Modifier.padding(bottom = 4.dp).size(48.dp), enabled = message.isNotBlank() && !sending,
                colors = IconButtonDefaults.filledIconButtonColors(containerColor = MaterialTheme.colorScheme.onSurface, contentColor = MaterialTheme.colorScheme.surface,
                    disabledContainerColor = Panel, disabledContentColor = Muted)) {
                if (sending) CircularProgressIndicator(Modifier.size(18.dp), color = Muted, strokeWidth = 2.dp)
                else Icon(Icons.AutoMirrored.Rounded.Send, "Send message", Modifier.size(20.dp))
            }
        }
        }
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
        Text("Public chat · Be kind to fellow fans", color = Muted, style = MaterialTheme.typography.labelSmall)
    }
}
