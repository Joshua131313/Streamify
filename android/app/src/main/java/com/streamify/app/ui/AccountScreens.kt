package com.streamify.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.streamify.app.*
import com.streamify.app.R
import com.streamify.app.data.*
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlin.coroutines.coroutineContext

@Composable
fun AccountScreen(vm: StreamifyViewModel) {
    val context = LocalContext.current
    val activity = remember(context) { generateSequence(context) { (it as? android.content.ContextWrapper)?.baseContext }.filterIsInstance<android.app.Activity>().firstOrNull() }
    val scope = rememberCoroutineScope()
    val account = vm.account
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    fun perform(action: suspend () -> Unit) {
        if (busy) return
        busy = true; message = null
        scope.launch {
            try { action() }
            catch (_: GetCredentialCancellationException) { message = "Sign-in cancelled." }
            catch (_: NoCredentialException) { message = "No Google account is available. Add one in your device’s Settings, then try again." }
            catch (error: Exception) { coroutineContext.ensureActive(); message = error.localizedMessage ?: "Please try again." }
            finally { busy = false }
        }
    }
    LazyColumn(contentPadding = PaddingValues(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        item { ScreenHeading("Account", vm::back) }
        item { SecondaryButton(onClick = { com.streamify.app.downloads.openDownloads(context) }, modifier = Modifier.padding(horizontal = 20.dp).fillMaxWidth()) { Icon(Icons.Rounded.Download, null); Spacer(Modifier.width(10.dp)); Text("View downloads") } }
        item { PagePanel(Modifier.padding(horizontal = 20.dp)) {
            Icon(Icons.Rounded.AccountCircle, null, Modifier.size(64.dp), tint = StreamRed)
            Text(if (account.uid == null) "Pick up where you left off." else account.name.ifBlank { "Welcome back" }, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            if (account.uid == null) {
                Text("Continue with Google to sync your saved titles, episodes, teams, searches, and favorite genres with the web app.", color = Muted)
                Button(onClick = { perform {
                    val option = GetSignInWithGoogleOption.Builder(context.getString(R.string.default_web_client_id)).build()
                    val result = CredentialManager.create(context).getCredential(activity ?: error("Open sign-in from the app."), GetCredentialRequest.Builder().addCredentialOption(option).build())
                    val credential = result.credential as? CustomCredential ?: error("Google did not return a sign-in credential.")
                    check(credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) { "Unsupported Google sign-in response." }
                    vm.accounts.signInGoogle(GoogleIdTokenCredential.createFrom(credential.data).idToken)
                } }, enabled = !busy, modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp), colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onSurface, contentColor = MaterialTheme.colorScheme.surface)) { Text(if (busy) "Connecting…" else "Continue with Google") }
                SecondaryButton(onClick = vm::back, enabled = !busy) { Text("Continue as guest") }
            } else {
                Text(account.email, color = Muted)
                Text(when { account.loading -> "Loading your account…"; account.pendingWrites -> "Changes waiting to sync"; account.offline -> "Showing cached account data"; else -> "Connected to your web account" }, color = Muted)
                Button(onClick = { vm.navigate(Destination.Preferences) }, enabled = !account.loading, modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp)) { Text(if (account.onboardingComplete) "Genres & followed teams" else "Finish account setup") }
                SecondaryButton(onClick = { vm.accounts.retrySync() }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("Refresh account sync") }
                SecondaryButton(onClick = { perform {
                    vm.accounts.signOut()
                    try { CredentialManager.create(context).clearCredentialState(ClearCredentialStateRequest()) } catch (_: Exception) { coroutineContext.ensureActive() }
                } }, enabled = !busy, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("Sign out") }
                Text("Guest browsing stays separate on this device. Signing out restores your guest library.", color = Muted, style = MaterialTheme.typography.bodySmall)
            }
        } }
        if (busy) item { Loading() }
        message?.let { item { Text(it, Modifier.padding(horizontal = 20.dp), color = MaterialTheme.colorScheme.error) } }
        account.error?.let { item { ErrorBanner(it) { vm.accounts.retrySync() } } }
    }
}
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PreferencesScreen(vm: StreamifyViewModel) {
    val account = vm.account
    val scope = rememberCoroutineScope()
    var chosen by rememberSaveable(account.uid) { mutableStateOf(account.genres.toList()) }
    var league by rememberSaveable { mutableStateOf(League.NBA) }
    var retry by remember { mutableIntStateOf(0) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val genres by produceState(LoadState<List<Genre>>(loading = true), retry) {
        value = LoadState(loading = true)
        try { value = LoadState(coroutineScope { val movies = async { vm.repository.genres(MediaType.MOVIE) }; val tv = async { vm.repository.genres(MediaType.TV) }; (movies.await() + tv.await()).distinctBy { it.id }.sortedBy { it.name } }) }
        catch (failure: Exception) { coroutineContext.ensureActive(); value = LoadState(error = failure.localizedMessage) }
    }
    val teams by produceState(LoadState<List<LeagueTeam>>(loading = true), league, retry) {
        value = LoadState(loading = true)
        try { value = LoadState(SportsData.teams(league)) } catch (failure: Exception) { coroutineContext.ensureActive(); value = LoadState(error = failure.localizedMessage) }
    }
    if (account.uid == null) { Message("Sign in to customize", "Your favorite genres and teams will follow you across devices.", "Sign in", { vm.back(); vm.navigate(Destination.Account) }); return }
    LazyColumn(contentPadding = PaddingValues(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        item { ScreenHeading("Make it yours", vm::back) }
        item { SectionLabel("Favorite genres", "Choose the stories you want to see more of.", Modifier.padding(horizontal = 20.dp)) }
        if (genres.loading) item { Loading() }
        genres.error?.let { item { ErrorBanner(it) { retry++ } } }
        item { FlowRow(Modifier.padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            genres.data.orEmpty().forEach { genre -> val id = genre.id.toString(); FilterPill(genre.name, id in chosen, { chosen = if (id in chosen) chosen - id else chosen + id }, enabled = !busy) }
        } }
        item { Button(onClick = { if (!busy) { busy = true; error = null; scope.launch {
            try { vm.accounts.savePreferences(chosen.toSet()); vm.back() }
            catch (failure: Exception) { coroutineContext.ensureActive(); error = failure.localizedMessage }
            finally { busy = false }
        } } }, enabled = !busy && !account.loading, modifier = Modifier.padding(horizontal = 20.dp).fillMaxWidth().heightIn(min = 50.dp)) { Text(if (busy) "Saving…" else "Save preferences") } }
        if (!account.onboardingComplete) item { SecondaryButton(onClick = { if (!busy) { busy = true; scope.launch {
            try { vm.accounts.savePreferences(account.genres); vm.back() } catch (failure: Exception) { coroutineContext.ensureActive(); error = failure.localizedMessage } finally { busy = false }
        } } }, enabled = !busy, modifier = Modifier.padding(horizontal = 20.dp)) { Text("Skip for now") } }
        error?.let { item { Text(it, Modifier.padding(horizontal = 20.dp), color = MaterialTheme.colorScheme.error) } }
        item { SectionLabel("Follow your teams", "Team choices sync as you select them.", Modifier.padding(horizontal = 20.dp)) }
        item { LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(League.entries) { item -> FilterPill(item.name, league == item, { league = item }, leading = { LeagueLogo(item, Modifier.size(26.dp)) }) }
        } }
        if (teams.loading) item { Loading() }
        teams.error?.let { item { ErrorBanner(it) { retry++ } } }
        items(teams.data.orEmpty(), key = { "${it.league}:${it.team.id}" }) { item ->
            Surface(Modifier.fillMaxWidth().padding(horizontal = 20.dp), shape = RoundedCornerShape(16.dp), color = Panel) {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                RemoteImage(item.team.logo, null, Modifier.size(40.dp).padding(3.dp), androidx.compose.ui.layout.ContentScale.Fit); Text(item.team.name, Modifier.weight(1f).padding(start = 12.dp))
                Checkbox(vm.isFollowing(item.league, item.team), { vm.toggleTeam(item.league, item.team) }, enabled = !account.loading)
            }
            }
        }
    }
}
