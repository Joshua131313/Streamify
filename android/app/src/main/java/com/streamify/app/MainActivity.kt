package com.streamify.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.foundation.clickable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.streamify.app.data.*
import com.streamify.app.ui.*

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        if (android.os.Build.VERSION.SDK_INT >= 31) {
            splashScreen.setOnExitAnimationListener { it.remove() }
        }
        setContent { StreamifyTheme {
            LaunchReveal(animate = savedInstanceState == null) {
                StreamifyApp(openAccount = intent.getBooleanExtra("openAccount", false))
            }
        } }
    }
}

@Composable
private fun StreamifyApp(vm: StreamifyViewModel = viewModel(), openAccount: Boolean = false) {
    var settings by rememberSaveable { mutableStateOf(false) }
    val pageState = rememberSaveableStateHolder()
    LaunchedEffect(Unit) { if (openAccount && vm.destination != Destination.Account) vm.navigate(Destination.Account) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_RESUME) vm.refreshLocal() }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    BackHandler(settings || vm.destination != null || vm.tab != "Home") {
        when { settings -> settings = false; vm.destination != null -> vm.back(); else -> vm.tab = "Home" }
    }
    val root = !settings && vm.destination == null
    val bottomInset = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    val topTint = if (Canvas.luminance() < .5f) Color(0xFF302735) else Color(0xFFE7DFEC)
    val backdrop = Brush.verticalGradient(listOf(topTint, Canvas), endY = with(LocalDensity.current) { 420.dp.toPx() })
    Scaffold(modifier = Modifier.background(backdrop), containerColor = Color.Transparent, contentColor = MaterialTheme.colorScheme.onBackground,
        contentWindowInsets = WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal)) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            Box(Modifier.fillMaxSize()) {
                Column(Modifier.fillMaxSize().alpha(if (root) 1f else 0f).then(if (root) Modifier else Modifier.clearAndSetSemantics { })) {
                    AppHeader(title = when (vm.tab) { "Browse" -> "Search"; "Library" -> "My list"; else -> vm.tab },
                        search = { if (vm.tab == "Sports") vm.sportsSearchRequested = true else { vm.mediaSearchRequest++; vm.tab = "Browse" } }, library = { vm.tab = "Library" },
                        account = { vm.navigate(Destination.Account) }, settings = { settings = true })
                    if (vm.account.error != null) ErrorBanner(vm.account.error!!) { vm.accounts.retrySync() }
                    pageState.SaveableStateProvider(vm.tab) { when (vm.tab) {
                        "Home" -> HomeScreen(vm, active = root) { settings = true }
                        "Browse" -> BrowseScreen(vm)
                        "Sports" -> SportsScreen(vm)
                        "Library" -> LibraryScreen(vm)
                    } }
                }
            if (!root) Box(Modifier.fillMaxSize().background(Canvas).padding(bottom = bottomInset).clickable(interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null) {}) {
            when {
                settings -> SettingsScreen(vm) { settings = false }
                vm.destination == Destination.Account -> AccountScreen(vm)
                vm.destination == Destination.Preferences -> PreferencesScreen(vm)
                vm.destination == Destination.Collections -> CollectionsScreen(vm)
                vm.destination == Destination.MultiWatch -> MultiWatchScreen(vm)
                vm.destination is Destination.CollectionDetail -> CollectionScreen((vm.destination as Destination.CollectionDetail).collection, vm)
                vm.destination is Destination.PersonDetail -> PersonScreen((vm.destination as Destination.PersonDetail).id, vm)
                vm.destination is Destination.TeamDetail -> TeamScreen(vm.destination as Destination.TeamDetail, vm)
                vm.selected != null -> DetailScreen(vm.selected!!, vm) { vm.selected = null }
                vm.selectedGame != null -> GameScreen(vm.selectedGame!!, vm) { vm.selectedGame = null }
                else -> Unit
            }
            }
            }
            if (root) StreamifyBottomBar(vm.tab, Modifier.align(Alignment.BottomCenter)) { if (it == "Browse") vm.mediaSearchRequest++; vm.tab = it }
        }
    }
}

@Composable
private fun SettingsScreen(vm: StreamifyViewModel, back: () -> Unit) {
    var key by remember { mutableStateOf(vm.store.tmdbKey) }
    var api by remember { mutableStateOf(vm.store.apiBase) }
    var server by remember { mutableStateOf(vm.store.serverId) }
    var error by remember { mutableStateOf<String?>(null) }
    var theme by remember { mutableStateOf(vm.store.theme) }
    LazyColumn(contentPadding = PaddingValues(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        item { ScreenHeading("Settings", back) }
        item { AppUpdatePanel() }
        item { PagePanel(Modifier.padding(horizontal = 20.dp)) {
            SectionLabel("Your account", "Keep your favorites with you on every device.")
            SecondaryButton(onClick = { back(); vm.navigate(Destination.Account) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text(if (vm.account.uid == null) "Sign in with Google" else "Manage account") }
        } }
        item { PagePanel(Modifier.padding(horizontal = 20.dp)) {
            SectionLabel("Appearance")
            LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) { items(listOf("Dark", "Light", "System")) { value -> FilterPill(value, theme == value, { theme = value; vm.store.theme = value }) } }
        } }
        item { PagePanel(Modifier.padding(horizontal = 20.dp)) {
            SectionLabel("Catalog & connections")
            OutlinedTextField(key, { key = it }, label = { Text("TMDB access token") }, shape = RoundedCornerShape(12.dp), visualTransformation = PasswordVisualTransformation(), singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(api, { api = it }, label = { Text("Sports backend URL") }, shape = RoundedCornerShape(12.dp), singleLine = true, modifier = Modifier.fillMaxWidth())
            Text("Optional. Leave empty to use ESPN directly. A custom backend must support /api/schedule.", color = Muted, style = MaterialTheme.typography.bodySmall)
        } }
        item { Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            SectionLabel("Default video provider")
            vm.store.servers.forEach { provider ->
                Surface(onClick = { server = provider.id }, shape = RoundedCornerShape(16.dp), color = if (server == provider.id) StreamRed.copy(alpha = .12f) else Panel) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(server == provider.id, null); Text(provider.label, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
        } }
        error?.let { item { Text(it, Modifier.padding(horizontal = 20.dp), color = MaterialTheme.colorScheme.error) } }
        item { Button(onClick = {
            if (api.isNotBlank() && !httpsUrl(api.trim())) error = "Enter a valid HTTPS URL, or leave the backend empty."
            else { vm.saveSettings(key, api, server); back() }
        }, modifier = Modifier.padding(horizontal = 20.dp).fillMaxWidth().heightIn(min = 50.dp)) { Text("Save settings") } }
        item { Text("Streamify for Android · ${BuildConfig.VERSION_NAME}\n\nSign in to sync your library, episode history, searches, preferences, and followed teams with the web app. Guest data stays separate on this device.\n\nThis product uses the TMDB API but is not endorsed or certified by TMDB. Sports data comes from ESPN. Playback is provided by external services and availability varies.", Modifier.padding(horizontal = 24.dp), color = Muted, style = MaterialTheme.typography.bodySmall) }
    }
}
