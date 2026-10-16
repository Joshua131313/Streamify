package com.streamify.app

import android.content.Context
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.*
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.streamify.app.data.*
import com.streamify.app.ui.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.tasks.await
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class SportsChatUiTest {
    @Test fun sportsHeaderOpensSportsSearchAndLiveFilter() {
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        Configurator.getInstance().waitForIdleTimeout = 100
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity -> androidx.lifecycle.ViewModelProvider(activity)[StreamifyViewModel::class.java].tab = "Sports" }
            assertNotNull(device.wait(Until.findObject(By.text("Live now")), 10000))
            assertFalse(device.hasObject(By.text("Browse leagues")))
            device.findObject(By.text("Live now")).click()
            assertNotNull(device.wait(Until.findObject(By.text("All leagues schedule")), 5000))
            assertFalse(device.hasObject(By.text("Calendar")))
            assertFalse(device.hasObject(By.text("Today")))
            device.findObject(By.desc("Search")).click()
            assertNotNull(device.wait(Until.findObject(By.text("Search sports")), 5000))
            scenario.onActivity { activity -> assertEquals("Sports", androidx.lifecycle.ViewModelProvider(activity)[StreamifyViewModel::class.java].tab) }
        }
    }
    @Test fun repliesReactionsAndSportsLayout() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val app = FirebaseApp.initializeApp(context, FirebaseOptions.Builder().setProjectId("demo-streamify-chat")
            .setApplicationId("demo-test").setApiKey("demo-test").build(), "chat-ui-${System.nanoTime()}")
        val auth = FirebaseAuth.getInstance(app).also { it.useEmulator("10.0.2.2", 9098) }
        val db = FirebaseFirestore.getInstance(app).also { it.useEmulator("10.0.2.2", 8086) }
        val store = LocalStore(context) { auth.currentUser?.takeUnless { it.isAnonymous }?.uid }
        val originalGuestHistory = store.history.filterNot { it.media.id == 550 && it.media.title == "Progress fixture" }
        val account = AccountRepository(auth, db, store) { id, type -> Media(id, type, "Test") }
        try {
            val movie = Media(550, MediaType.MOVIE, "Progress fixture")
            account.savePlayback(History(movie, positionSeconds = 120.0, durationSeconds = 3600.0), null, true)
            assertEquals(120.0, store.history.first { it.media.key == movie.key }.positionSeconds, .01)
            auth.createUserWithEmailAndPassword("progress-${System.nanoTime()}@example.test", "test-password-123").await()
            val owner = auth.currentUser!!.uid
            withTimeout(10000) { account.account.first { it.uid == owner && !it.loading } }
            account.savePlayback(History(movie, positionSeconds = 180.0, durationSeconds = 3600.0), owner, true)
            val saved = withTimeout(10000) { db.collection("users").document(owner).collection("watchHistory").document("movie-550").snapshotsForProgress() }
            assertEquals(180.0, (saved.get("positionSeconds") as Number).toDouble(), .01)
            auth.signOut()
            withTimeout(10000) { account.account.first { it.uid == null } }
            account.savePlayback(History(movie, positionSeconds = 999.0, durationSeconds = 3600.0), owner, true)
            assertEquals(120.0, store.history.first { it.media.key == movie.key }.positionSeconds, .01)
            val chat = LiveChatRepository(auth, db)
            val room = "ui-${System.nanoTime()}"
            chat.send(room, "What a catch! Who else is watching?")
            val first = withTimeout(10000) { chat.messages(room).first { it.messages.size == 1 }.messages.single() }
            chat.react(room, first.id, chatReactions.first())
            chat.send(room, "@${first.handle()} That was incredible!", first)
            val messages = withTimeout(10000) { chat.messages(room).first { it.messages.size == 2 }.messages }
            assertEquals(first.id, messages.last().reply?.id)
            assertEquals(chatReactions.first(), messages.first().votes[auth.currentUser!!.uid])
            val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
            Configurator.getInstance().waitForIdleTimeout = 100
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity { activity -> activity.setContent { StreamifyTheme { Surface { Column(Modifier.fillMaxSize().statusBarsPadding().padding(top = 20.dp)) { LiveChatRoom(room, account) {} } } } } }
                assertNotNull(device.wait(Until.findObject(By.textContains("That was incredible!")), 10000))
                device.findObjects(By.desc("Reply to message")).last().click()
                assertNotNull(device.wait(Until.findObject(By.textStartsWith("Replying to")), 5000))
                device.takeScreenshot(File(context.getExternalFilesDir(null), "chat-sections.png"))
                val game = Game("fixture", League.MLB, "2026-10-15T23:00:00Z", "in", "Top 7th", Team("1", "New York Yankees", "NYY", "", "3", ""), Team("2", "Toronto Blue Jays", "TOR", "", "2", ""), "", "", "",
                    BaseballLive(true, false, true, 2, 1, 2, "Aaron Judge", "", "1 for 3 · Single, RBI"))
                scenario.onActivity { activity -> activity.setContent { StreamifyTheme { Surface { Column(Modifier.fillMaxSize().statusBarsPadding(), verticalArrangement = Arrangement.spacedBy(24.dp)) { GameCard(game) {}; ScoringTable(game, (1..7).map { StatRow("Inning $it", if (it == 3) "2" else "0", if (it == 4) "3" else "0") }); ContinueWatchingShelf(listOf(History(Media(1, MediaType.MOVIE, "Movie in progress"), positionSeconds = 1200.0, durationSeconds = 5400.0)), "streamex") } } } } }
                device.wait(Until.findObject(By.text("Batter & pitcher")), 5000).click()
                assertNotNull(device.wait(Until.findObject(By.text("Aaron Judge")), 5000))
                assertNotNull(device.wait(Until.findObject(By.text("Team")), 5000))
                device.takeScreenshot(File(context.getExternalFilesDir(null), "mlb-table.png"))
            }
        } finally { auth.signOut(); store.history = originalGuestHistory; account.close(); db.terminate().await(); app.delete() }
        Unit
    }
}

private suspend fun com.google.firebase.firestore.DocumentReference.snapshotsForProgress(): com.google.firebase.firestore.DocumentSnapshot {
    while (true) {
        val snapshot = get(com.google.firebase.firestore.Source.SERVER).await()
        if ((snapshot.get("positionSeconds") as? Number)?.toDouble() == 180.0) return snapshot
        delay(100)
    }
}
