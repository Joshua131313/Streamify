package com.streamify.app

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreSettings
import com.google.firebase.firestore.MemoryCacheSettings
import com.google.firebase.firestore.Source
import com.streamify.app.data.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.tasks.await
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith
import java.util.Date
import java.util.UUID
import org.json.JSONObject

/** These tests use a named demo FirebaseApp and localhost emulators exclusively. Never real users or games. */
@RunWith(AndroidJUnit4::class)
class AccountIntegrationTest {
    private lateinit var app: FirebaseApp
    private lateinit var auth: FirebaseAuth
    private lateinit var db: FirebaseFirestore
    private lateinit var repo: AccountRepository
    private lateinit var store: LocalStore
    private val testId = UUID.randomUUID().toString()
    private val email get() = "android-$testId@example.test"
    // Mock Google credentials are accepted only by the named local demo Auth emulator.
    private fun googleToken(subject: String = testId) = JSONObject().put("sub", subject).put("email", if (subject == testId) email else "second-$email")
        .put("email_verified", true).put("name", "Android Tester").toString()
    private val movie = Media(157336, MediaType.MOVIE, "Interstellar", genreIds = listOf(12, 18, 878))
    @Before fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        app = FirebaseApp.initializeApp(context, FirebaseOptions.Builder().setProjectId("demo-streamify-android")
            .setApplicationId("1:123456789:android:test").setApiKey("demo-emulator-$testId").build(), "account-$testId")
        check(app.options.projectId!!.startsWith("demo-"))
        auth = FirebaseAuth.getInstance(app).also { it.useEmulator("10.0.2.2", 9099) }
        db = FirebaseFirestore.getInstance(app).also {
            it.firestoreSettings = FirebaseFirestoreSettings.Builder().setLocalCacheSettings(MemoryCacheSettings.newBuilder().build()).build()
            it.useEmulator("10.0.2.2", 8085)
        }
        store = LocalStore(context) { auth.currentUser?.uid }
        store.saved = emptyList(); store.history = emptyList(); store.favorites = emptySet(); store.searches = emptyList()
        repo = AccountRepository(auth, db, store) { id, type -> Media(id, type, "Loaded $id ${type.path}") }
    }
    @After fun tearDown() = runBlocking {
        if (::repo.isInitialized) repo.close()
        if (::auth.isInitialized) auth.signOut()
        if (::db.isInitialized) db.terminate().await()
        if (::app.isInitialized) app.delete()
    }
    private suspend fun eventually(condition: () -> Boolean) { withTimeout(25_000) { while (!condition()) delay(80) } }
    private suspend fun register() {
        repo.signInGoogle(googleToken())
        eventually { repo.account.value.uid == auth.currentUser?.uid && !repo.account.value.loading && !repo.account.value.offline }
        assertNull(repo.account.value.error)
    }

    @Test fun accountSwitchPreservesGuestLibraryAndExistingOnboarding() = runBlocking {
        repo.toggleSaved(movie)
        eventually { repo.library.value.saved.size == 1 }
        register()
        val uid = auth.currentUser!!.uid
        assertTrue(repo.library.value.saved.isEmpty())
        repo.savePreferences(setOf("12", "878"))
        eventually { repo.account.value.onboardingComplete && repo.account.value.genres == setOf("12", "878") }
        val created = db.collection("users").document(uid).get(Source.SERVER).await().getTimestamp("createdAt")
        repo.signOut()
        eventually { repo.account.value.uid == null && repo.library.value.saved.singleOrNull()?.id == movie.id }
        repo.signInGoogle(googleToken())
        eventually { repo.account.value.uid == uid && repo.account.value.onboardingComplete && !repo.account.value.loading }
        assertTrue(repo.library.value.saved.isEmpty())
        val profile = db.collection("users").document(uid).get(Source.SERVER).await()
        assertEquals(created, profile.getTimestamp("createdAt"))
        assertEquals("Android", profile.getString("firstName"))
        assertEquals(setOf("12", "878"), repo.account.value.genres)
    }

    @Test fun readsWebDocumentsAndWritesCompatibleMediaEpisodeTeamAndSearchData() = runBlocking {
        register()
        val root = db.collection("users").document(auth.currentUser!!.uid)
        val saved = root.collection("savedMedia")
        saved.document("web-generated-id").set(mapOf("mediaId" to movie.id, "mediaType" to "movie")).await()
        saved.document("legacy-duplicate").set(mapOf("mediaId" to movie.id, "mediaType" to "movie")).await()
        saved.document("same-id-different-type").set(mapOf("mediaId" to movie.id, "mediaType" to "tv")).await()
        eventually { repo.library.value.saved.size == 2 }
        repo.toggleSaved(movie)
        eventually { repo.library.value.saved.size == 1 && repo.library.value.saved.first().type == MediaType.TV }
        assertEquals(1, saved.get(Source.SERVER).await().size())
        repo.toggleSaved(movie)
        eventually { repo.library.value.saved.size == 2 }
        assertEquals("movie", saved.document("movie-${movie.id}").get(Source.SERVER).await().getString("mediaType"))
        val show = Media(136315, MediaType.TV, "The Bear", genreIds = listOf(18, 35))
        repo.record(show, 2, 3)
        eventually { repo.library.value.history.firstOrNull()?.episode == 3 }
        val history = root.collection("watchHistory").document("tv-136315").get(Source.SERVER).await()
        assertEquals(2L, history.getLong("season")); assertEquals(3L, history.getLong("episode"))
        assertEquals(listOf(18L, 35L), history.get("genreIds"))
        root.collection("watchHistory").document("tv-136315").update(mapOf("episode" to 4, "updatedAt" to Timestamp.now())).await()
        eventually { repo.library.value.history.firstOrNull()?.episode == 4 }
        val team = Team("13", "Los Angeles Lakers", "LAL", "", "", "")
        root.collection("favoriteTeams").document("web-team-id").set(mapOf("abbrev" to "LAL", "league" to "NBA", "name" to team.name)).await()
        eventually { repo.isFollowing(League.NBA, team) }
        repo.toggleTeam(League.NBA, team)
        eventually { !repo.isFollowing(League.NBA, team) }
        assertFalse(root.collection("favoriteTeams").document("web-team-id").get(Source.SERVER).await().exists())
        repo.toggleTeam(League.NBA, team)
        eventually { repo.isFollowing(League.NBA, team) }
        assertEquals("LAL", root.collection("favoriteTeams").document("NBA-LAL").get(Source.SERVER).await().getString("abbrev"))
        root.collection("searchHistory").document("web-search").set(mapOf("searchValue" to "Arrival", "timeStamp" to Timestamp.now())).await()
        eventually { "Arrival" in repo.library.value.searches }
        repo.rememberSearch("Interstellar")
        eventually { repo.library.value.searches.firstOrNull() == "Interstellar" }
        repo.clearSearches()
        eventually { repo.library.value.searches.isEmpty() }
        assertTrue(root.collection("searchHistory").get(Source.SERVER).await().isEmpty)
        repo.removeHistory(show)
        eventually { repo.library.value.history.isEmpty() }
    }

    @Test fun chatSharesWebSchemaAndSupportsGuests() = runBlocking {
        register()
        val chat = LiveChatRepository(auth, db)
        val room = "test-$testId"
        chat.send(room, "Local emulator integration check")
        val messages = withTimeout(15_000) { chat.messages(room).first { it.messages.isNotEmpty() } }.messages
        assertEquals("Android Tester", messages.single().sender)
        assertEquals(auth.currentUser!!.uid, messages.single().uid)
        assertEquals("Local emulator integration check", messages.single().message)
        val document = db.collection("live-chats").document(room).get(Source.SERVER).await()
        assertTrue(document.getTimestamp("expiresAt")!!.toDate().after(Date()))
        repo.signOut()
        val publicMessages = withTimeout(15_000) { chat.messages(room).first { !it.loading } }
        assertNull(publicMessages.error)
        assertEquals(1, publicMessages.messages.size)
        assertTrue(runCatching { chat.send(room, "   ") }.isFailure)
        assertNull(auth.currentUser)
        chat.send(room, "Hello from a guest")
        assertTrue(auth.currentUser!!.isAnonymous)
        val guestMessages = withTimeout(15_000) { chat.messages(room).first { it.messages.size == 2 } }.messages
        assertTrue(guestMessages.any { it.uid == auth.currentUser!!.uid && it.sender.startsWith("Guest ") })
        eventually { repo.account.value.uid == null }
    }

    @Test fun legacyAccountFieldsDoNotCrashAfterGoogleReturn() = runBlocking {
        register()
        val uid = auth.currentUser!!.uid
        val root = db.collection("users").document(uid)
        root.update(mapOf("firstName" to 42, "lastName" to false, "onboardingComplete" to "true")).await()
        root.collection("watchHistory").document("legacy-episode").set(mapOf(
            "mediaId" to movie.id, "mediaType" to "movie", "season" to "2", "episode" to "3", "updatedAt" to Timestamp.now())).await()
        root.collection("favoriteTeams").document("malformed").set(mapOf("league" to 99, "abbrev" to false)).await()
        root.collection("searchHistory").document("malformed").set(mapOf("searchValue" to listOf("invalid"), "timeStamp" to Timestamp.now())).await()
        repo.signOut()
        repo.signInGoogle(googleToken())
        eventually { repo.account.value.uid == uid && !repo.account.value.loading && repo.library.value.history.isNotEmpty() }
        assertEquals(2, repo.library.value.history.first().season)
        assertEquals(3, repo.library.value.history.first().episode)
        assertEquals("Android Tester", repo.account.value.name)
        assertNull(repo.account.value.error)
    }

    @Test fun otherAccountCannotReadFirstAccountsPrivateLibrary() = runBlocking {
        register()
        val firstUid = auth.currentUser!!.uid
        repo.toggleSaved(movie)
        eventually { repo.library.value.saved.size == 1 }
        repo.signOut()
        repo.signInGoogle(googleToken("second-$testId"))
        eventually { !repo.account.value.loading && repo.account.value.uid == auth.currentUser?.uid }
        assertNotEquals(firstUid, auth.currentUser!!.uid)
        assertTrue(repo.library.value.saved.isEmpty())
        assertTrue(runCatching { db.collection("users").document(firstUid).get(Source.SERVER).await() }.isFailure)
        assertTrue(runCatching { db.collection("users").document(firstUid).collection("savedMedia").get(Source.SERVER).await() }.isFailure)
    }

    @Test fun offlineChangesQueueAndUploadAfterReconnect() = runBlocking {
        register()
        db.disableNetwork().await()
        repo.toggleSaved(movie)
        eventually { repo.library.value.saved.any { it.key == movie.key } && repo.account.value.pendingWrites }
        assertTrue(repo.account.value.offline)
        db.enableNetwork().await()
        eventually { !repo.account.value.pendingWrites && !repo.account.value.offline }
        val saved = db.collection("users").document(auth.currentUser!!.uid).collection("savedMedia").document("movie-${movie.id}").get(Source.SERVER).await()
        assertEquals(movie.id.toLong(), saved.getLong("mediaId"))
    }
}
