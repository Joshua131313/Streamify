package com.streamify.app.data

import android.content.Context
import com.google.android.gms.tasks.Task
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.auth.GoogleAuthProvider
import com.google.firebase.firestore.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.tasks.await
import java.security.MessageDigest
import java.util.Date

data class AccountState(
    val uid: String? = null, val name: String = "", val email: String = "", val genres: Set<String> = emptySet(),
    val onboardingComplete: Boolean = true, val loading: Boolean = false, val error: String? = null,
    val pendingWrites: Boolean = false, val offline: Boolean = false
)
data class LibraryState(val saved: List<Media>, val history: List<History>, val favorites: Set<String>, val searches: List<String>)

/** One session per app. Every callback is guarded against account changes. Guest data is never uploaded implicitly. */
class AccountRepository(
    val auth: FirebaseAuth, val db: FirebaseFirestore, val store: LocalStore,
    private val mediaLoader: suspend (Int, MediaType) -> Media
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val _account = MutableStateFlow(AccountState())
    val account = _account.asStateFlow()
    private val _library = MutableStateFlow(localLibrary())
    val library = _library.asStateFlow()
    private val listeners = mutableListOf<ListenerRegistration>()
    private val snapshots = mutableMapOf<String, List<DocumentSnapshot>>()
    private val metadata = mutableMapOf<String, Pair<Boolean, Boolean>>()
    private val jobs = mutableMapOf<String, Job>()
    private val mediaCache = mutableMapOf<String, Media>()
    private val permits = Semaphore(6)
    private val playbackWrites = mutableMapOf<String, Job>()
    private val playbackWriteTimes = mutableMapOf<String, Long>()
    private var generation = 0
    private var closed = false
    private val authListener = FirebaseAuth.AuthStateListener { connect(it.currentUser?.takeUnless { user -> user.isAnonymous }) }

    init { auth.addAuthStateListener(authListener) }
    private fun localLibrary() = LibraryState(store.saved, store.history, store.favorites, store.searches)
    private fun publishLocal() { _library.value = localLibrary() }
    private fun current(uid: String, version: Int) = auth.currentUser?.uid == uid && generation == version

    private fun connect(user: FirebaseUser?) {
        if (closed) return
        playbackWrites.values.forEach { it.cancel() }; playbackWrites.clear()
        generation++
        val version = generation
        listeners.forEach { it.remove() }; listeners.clear()
        jobs.values.forEach { it.cancel() }; jobs.clear(); snapshots.clear(); metadata.clear(); mediaCache.clear()
        publishLocal()
        _account.value = AccountState(user?.uid, user?.displayName.orEmpty(), user?.email.orEmpty(), loading = user != null)
        if (user == null) return
        val uid = user.uid
        val root = db.collection("users").document(uid)
        listeners += root.addSnapshotListener(MetadataChanges.INCLUDE) { document, error ->
            if (!current(uid, version)) return@addSnapshotListener
            if (error != null) { report(error); _account.value = _account.value.copy(loading = false); return@addSnapshotListener }
            if (document == null) return@addSnapshotListener
            metadata["profile"] = document.metadata.hasPendingWrites() to document.metadata.isFromCache
            val name = listOf((document.get("firstName") as? String), (document.get("lastName") as? String)).filterNotNull().joinToString(" ").trim()
            _account.value = _account.value.copy(name = name.ifBlank { user.displayName.orEmpty() },
                genres = (document.get("favoriteGenres") as? List<*>)?.mapNotNull { it?.toString()?.takeIf { s -> s.toIntOrNull() != null } }?.toSet().orEmpty(),
                onboardingComplete = (document.get("onboardingComplete") as? Boolean) ?: false,
                loading = !document.exists() && document.metadata.isFromCache)
            updateStatus()
        }
        scope.launch {
            try { ensureProfile(user) } catch (error: Exception) { ensureActive(); if (current(uid, version)) report(error) }
        }
        listOf("savedMedia", "watchHistory", "favoriteTeams", "searchHistory").forEach { name ->
            val query: Query = when (name) {
                "watchHistory" -> root.collection(name).orderBy("updatedAt", Query.Direction.DESCENDING).limit(200)
                "searchHistory" -> root.collection(name).orderBy("timeStamp", Query.Direction.DESCENDING).limit(100)
                else -> root.collection(name)
            }
            listeners += query.addSnapshotListener(MetadataChanges.INCLUDE) { snapshot, error ->
                if (!current(uid, version)) return@addSnapshotListener
                if (error != null) { report(error); return@addSnapshotListener }
                if (snapshot == null) return@addSnapshotListener
                metadata[name] = snapshot.metadata.hasPendingWrites() to snapshot.metadata.isFromCache
                snapshots[name] = snapshot.documents
                updateStatus()
                jobs.remove(name)?.cancel()
                jobs[name] = scope.launch {
                  try {
                    when (name) {
                        "savedMedia" -> {
                            val items = hydrate(snapshot.documents)
                            if (current(uid, version)) store.saved = items.map { it.second }.distinctBy { it.key }
                        }
                        "watchHistory" -> {
                            val items = hydrate(snapshot.documents)
                            if (current(uid, version)) store.history = items.map { (doc, media) -> History(media,
                                cloudPositiveInt(doc.get("season")), cloudPositiveInt(doc.get("episode")),
                                (doc.get("updatedAt", DocumentSnapshot.ServerTimestampBehavior.ESTIMATE) as? com.google.firebase.Timestamp)?.toDate()?.time ?: 0L,
                                (doc.get("positionSeconds") as? Number)?.toDouble()?.takeIf { it.isFinite() && it >= 0 } ?: 0.0,
                                (doc.get("durationSeconds") as? Number)?.toDouble()?.takeIf { it.isFinite() && it > 0 } ?: 0.0)
                            }.map { remote -> store.history.firstOrNull { it.media.key == remote.media.key && it.watchedAt > remote.watchedAt } ?: remote }.sortedByDescending { it.watchedAt }.distinctBy { it.media.key }
                        }
                        "favoriteTeams" -> if (current(uid, version)) store.favorites = snapshot.documents.mapNotNull { doc ->
                            val league = League.entries.firstOrNull { it.name.equals((doc.get("league") as? String), true) } ?: return@mapNotNull null
                            (doc.get("abbrev") as? String)?.takeIf { it.isNotBlank() }?.let { teamCloudKey(league, it) }
                        }.toSet()
                        "searchHistory" -> if (current(uid, version)) store.searches = snapshot.documents.mapNotNull { (it.get("searchValue") as? String) }.distinct().take(12)
                    }
                    if (current(uid, version)) publishLocal()
                  } catch (failure: Exception) { ensureActive(); if (current(uid, version)) report(failure) }
                }
            }
        }
    }

    private suspend fun hydrate(documents: List<DocumentSnapshot>): List<Pair<DocumentSnapshot, Media>> = coroutineScope {
        val known = (_library.value.saved + _library.value.history.map { it.media }).associateBy { it.key }
        documents.map { document -> async {
            val ref = CloudMediaRef.parse(document.data.orEmpty()) ?: return@async null
            val media = known[ref.key]?.takeUnless { it.title.startsWith("Unavailable title #") } ?: mediaCache[ref.key] ?: permits.withPermit {
                try { mediaLoader(ref.id, ref.type).also { mediaCache[ref.key] = it } }
                catch (_: Exception) { ensureActive(); Media(ref.id, ref.type, "Unavailable title #${ref.id}") }
            }
            document to media
        } }.awaitAll().filterNotNull()
    }

    private fun updateStatus() {
        _account.value = _account.value.copy(loading = snapshots.size < 4 || !metadata.containsKey("profile"),
            pendingWrites = metadata.values.any { it.first }, offline = metadata.values.any { it.second })
    }
    private fun report(error: Exception) { _account.value = _account.value.copy(loading = false, error = error.localizedMessage ?: "Account sync failed. Please retry.") }
    fun clearError() { _account.value = _account.value.copy(error = null) }
    fun showError(error: Exception) { report(error) }
    fun retrySync() { connect(auth.currentUser?.takeUnless { it.isAnonymous }) }
    private fun track(task: Task<Void>, uid: String) {
        val version = generation
        task.addOnFailureListener { if (current(uid, version)) report(it) }
    }
    private fun collection(name: String): CollectionReference? {
        val uid = account.value.uid ?: return null
        if (!snapshots.containsKey(name)) { report(IllegalStateException("Your account data is still loading. Try again shortly.")); return null }
        return db.collection("users").document(uid).collection(name)
    }
    private fun mutate(name: String, action: (CollectionReference, String) -> Task<Void>) {
        val uid = account.value.uid ?: return
        val ref = collection(name) ?: return
        clearError(); track(action(ref, uid), uid)
    }

    fun toggleSaved(media: Media) {
        if (account.value.uid == null) {
            store.saved = if (store.saved.any { it.key == media.key }) store.saved.filterNot { it.key == media.key } else listOf(media) + store.saved
            publishLocal(); return
        }
        mediaCache[media.key] = media
        mutate("savedMedia") { ref, _ ->
            val existing = snapshots["savedMedia"].orEmpty().filter { CloudMediaRef.parse(it.data.orEmpty())?.key == media.key }
            if (existing.isEmpty()) ref.document("${media.type.path}-${media.id}").set(mapOf("mediaId" to media.id, "mediaType" to media.type.path))
            else db.batch().also { batch -> existing.forEach { batch.delete(it.reference) } }.commit()
        }
    }
    fun record(media: Media, season: Int = 1, episode: Int = 1) {
        val realUid = auth.currentUser?.takeUnless { it.isAnonymous }?.uid
        if (realUid != account.value.uid || (realUid != null && !snapshots.containsKey("watchHistory"))) return
        val previous = store.history.firstOrNull { it.media.key == media.key && it.season == season && it.episode == episode }
        if (previous != null || snapshots["watchHistory"].orEmpty().any { doc ->
            CloudMediaRef.parse(doc.data.orEmpty())?.key == media.key && cloudPositiveInt(doc.get("season")) == season && cloudPositiveInt(doc.get("episode")) == episode
        }) return
        val entry = History(media, season, episode)
        if (account.value.uid == null) { store.history = listOf(entry) + store.history.filterNot { it.media.key == media.key }; publishLocal(); return }
        mediaCache[media.key] = media
        // Preserve existing progress even while media metadata is still being hydrated.
        val uid = account.value.uid ?: return
        val payload = mutableMapOf<String, Any>("mediaId" to media.id, "mediaType" to media.type.path,
            "genreIds" to media.genreIds, "updatedAt" to Timestamp(Date(entry.watchedAt)), "positionSeconds" to 0.0, "durationSeconds" to 0.0, "progressVersion" to 1)
        if (media.type == MediaType.TV) { payload["season"] = season.coerceAtLeast(1); payload["episode"] = episode.coerceAtLeast(1) }
        track(db.collection("users").document(uid).collection("watchHistory").document("${media.type.path}-${media.id}").set(payload, SetOptions.merge()), uid)
    }
    /** Progress is scoped to the identity that opened this player, never a later account. */
    fun savePlayback(entry: History, owner: String?, cloud: Boolean) {
        if (auth.currentUser?.takeUnless { it.isAnonymous }?.uid != owner) return
        store.history = listOf(entry) + store.history.filterNot { it.media.key == entry.media.key }
        publishLocal()
        if (!cloud || owner == null) return
        mediaCache[entry.media.key] = entry.media
        val payload = mapOf("mediaId" to entry.media.id, "mediaType" to entry.media.type.path, "genreIds" to entry.media.genreIds,
            "season" to entry.season, "episode" to entry.episode, "positionSeconds" to entry.positionSeconds,
            "durationSeconds" to entry.durationSeconds, "progressVersion" to 1, "updatedAt" to Timestamp(Date(entry.watchedAt)))
        val key = "$owner:${entry.media.key}"
        playbackWrites.remove(key)?.cancel()
        val version = generation
        playbackWrites[key] = scope.launch {
            delay(((playbackWriteTimes[key] ?: 0L) + 10_000 - System.currentTimeMillis()).coerceAtLeast(0))
            if (!current(owner, version)) return@launch
            playbackWriteTimes[key] = System.currentTimeMillis()
            track(db.collection("users").document(owner).collection("watchHistory").document("${entry.media.type.path}-${entry.media.id}").set(payload, SetOptions.merge()), owner)
        }
    }
    fun removeHistory(media: Media) {
        account.value.uid?.let { playbackWrites.remove("$it:${media.key}")?.cancel() }
        if (account.value.uid == null) { store.history = store.history.filterNot { it.media.key == media.key }; publishLocal(); return }
        mutate("watchHistory") { ref, _ -> db.batch().also { batch ->
            batch.delete(ref.document("${media.type.path}-${media.id}"))
            snapshots["watchHistory"].orEmpty().filter { CloudMediaRef.parse(it.data.orEmpty())?.key == media.key }.forEach { batch.delete(it.reference) }
        }.commit() }
    }
    fun isFollowing(league: League, team: Team) = teamCloudKey(league, team.abbreviation) in library.value.favorites || "${league.name}:${team.id}" in library.value.favorites
    fun toggleTeam(league: League, team: Team) {
        val key = teamCloudKey(league, team.abbreviation)
        if (account.value.uid == null) {
            store.favorites = if (isFollowing(league, team)) store.favorites - key - "${league.name}:${team.id}" else store.favorites + key
            publishLocal(); return
        }
        mutate("favoriteTeams") { ref, _ ->
            val existing = snapshots["favoriteTeams"].orEmpty().filter { (it.get("league") as? String).equals(league.name, true) && (it.get("abbrev") as? String)?.let { value -> teamCloudKey(league, value) } == key }
            if (existing.isEmpty()) ref.document(key.replace(':', '-')).set(mapOf("abbrev" to webTeamAbbreviation(league, team.abbreviation), "league" to league.name, "name" to team.name, "timeStamp" to FieldValue.serverTimestamp()))
            else db.batch().also { batch -> existing.forEach { batch.delete(it.reference) } }.commit()
        }
    }
    fun rememberSearch(value: String) {
        val term = value.trim().take(200).takeIf { it.isNotBlank() } ?: return
        if (account.value.uid == null) { store.searches = listOf(term) + store.searches.filterNot { it == term }; publishLocal(); return }
        val uid = account.value.uid ?: return
        val key = MessageDigest.getInstance("SHA-256").digest(term.toByteArray()).joinToString("") { "%02x".format(it) }
        track(db.collection("users").document(uid).collection("searchHistory").document(key).set(mapOf("searchValue" to term, "timeStamp" to FieldValue.serverTimestamp())), uid)
    }
    suspend fun clearSearches() {
        val uid = account.value.uid
        if (uid == null) { store.searches = emptyList(); publishLocal(); return }
        val ref = db.collection("users").document(uid).collection("searchHistory")
        // Read all pages, including entries outside the recent-search listener's limit.
        while (auth.currentUser?.uid == uid) {
            val page = ref.limit(400).get(Source.SERVER).await()
            if (page.isEmpty) break
            check(auth.currentUser?.uid == uid) { "Account changed." }
            db.batch().also { batch -> page.documents.forEach { batch.delete(it.reference) } }.commit().await()
        }
    }
    suspend fun ensureProfile(user: FirebaseUser = auth.currentUser ?: error("Sign in first.")) {
        val ref = db.collection("users").document(user.uid)
        db.runTransaction { tx ->
            if (!tx.get(ref).exists()) {
                val parts = user.displayName.orEmpty().trim().split(" ", limit = 2)
                tx.set(ref, mapOf("userId" to user.uid, "email" to user.email, "firstName" to parts.firstOrNull().orEmpty(),
                    "lastName" to parts.getOrNull(1).orEmpty(), "onboardingComplete" to false,
                    "createdAt" to FieldValue.serverTimestamp(), "updatedAt" to FieldValue.serverTimestamp()))
            }
        }.await()
    }
    suspend fun signInGoogle(idToken: String) { auth.signInWithCredential(GoogleAuthProvider.getCredential(idToken, null)).await(); ensureProfile() }
    suspend fun savePreferences(genres: Set<String>, complete: Boolean = true) {
        val uid = auth.currentUser?.uid ?: error("Sign in first.")
        ensureProfile()
        check(auth.currentUser?.uid == uid) { "Account changed." }
        db.collection("users").document(uid).update(mapOf("favoriteGenres" to genres.filter { it.toIntOrNull() != null }.take(40),
            "onboardingComplete" to complete, "updatedAt" to FieldValue.serverTimestamp())).await()
    }
    fun signOut() { auth.signOut() }
    suspend fun close() = withContext(Dispatchers.Main.immediate) {
        closed = true
        auth.removeAuthStateListener(authListener)
        listeners.forEach { it.remove() }; listeners.clear()
        scope.cancel()
    }

    companion object {
        @Volatile private var instance: AccountRepository? = null
        fun get(context: Context): AccountRepository = instance ?: synchronized(this) {
            instance ?: LocalStore(context.applicationContext).let { store -> AccountRepository(FirebaseAuth.getInstance(), FirebaseFirestore.getInstance(), store,
                { id, type -> StreamifyRepository(store).media(id, type) }).also { instance = it } }
        }
    }
}

internal fun cloudPositiveInt(value: Any?): Int = when (value) {
    is Number -> value.toInt()
    is String -> value.toIntOrNull() ?: 1
    else -> 1
}.coerceAtLeast(1)
