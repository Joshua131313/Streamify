package com.streamify.app

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.streamify.app.data.*
import com.streamify.app.data.Collection
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import java.time.LocalDate
import kotlin.coroutines.coroutineContext

data class Shelf(val title: String, val items: List<Media>)
data class LoadState<T>(val data: T? = null, val loading: Boolean = false, val error: String? = null)
sealed interface Destination {
    data class MediaDetail(val media: Media) : Destination
    data class GameDetail(val game: Game) : Destination
    data object Collections : Destination
    data object MultiWatch : Destination
    data object Account : Destination
    data object Preferences : Destination
    data class CollectionDetail(val collection: Collection) : Destination
    data class PersonDetail(val id: Int) : Destination
    data class TeamDetail(val league: League, val team: Team) : Destination
}

class StreamifyViewModel(application: Application) : AndroidViewModel(application) {
    val accounts = AccountRepository.get(application)
    val store = accounts.store
    var account by mutableStateOf(accounts.account.value); private set
    val repository = StreamifyRepository(store)
    val multiWatch = mutableStateListOf<Stream>()
    fun queueStream(stream: Stream) { if (multiWatch.none { it.url == stream.url } && multiWatch.size < 4) multiWatch.add(stream) }
    var tab by mutableStateOf("Home")
    private val destinations = mutableStateListOf<Destination>()
    val destination get() = destinations.lastOrNull()
    fun navigate(screen: Destination) { destinations.add(screen) }
    fun returnHome() { destinations.clear(); tab = "Home" }
    fun back() { if (destinations.isNotEmpty()) destinations.removeAt(destinations.lastIndex) }
    var selected: Media?
        get() = (destination as? Destination.MediaDetail)?.media
        set(value) { if (value == null) back() else navigate(Destination.MediaDetail(value)) }
    var selectedGame: Game?
        get() = (destination as? Destination.GameDetail)?.game
        set(value) { if (value == null) back() else navigate(Destination.GameDetail(value)) }
    var saved by mutableStateOf(store.saved); private set
    var history by mutableStateOf(store.history); private set
    var favorites by mutableStateOf(store.favorites); private set
    var home by mutableStateOf(LoadState<List<Shelf>>()); private set
    var catalog by mutableStateOf(LoadState<MediaPage>()); private set
    var sports by mutableStateOf(LoadState<Schedule>()); private set
    var query by mutableStateOf(""); private set
    var browseType by mutableStateOf(MediaType.MOVIE); private set
    var browseSort by mutableStateOf("popular"); private set
    var browseGenre by mutableStateOf(0); private set
    var browseProvider by mutableStateOf(0); private set
    var searches by mutableStateOf(store.searches); private set
    var sportsSearchRequested by mutableStateOf(false)
    var mediaSearchRequest by mutableStateOf(0)
    val discoveryCache = mutableMapOf<String, LoadState<MediaPage>>()
    var selectedLeagues by mutableStateOf(League.entries.toSet()); private set
    val league: League? get() = selectedLeagues.singleOrNull()
    var day by mutableStateOf(LocalDate.now()); private set
    var settingsRevision by mutableStateOf(0); private set
    private var homeJob: Job? = null
    private var catalogJob: Job? = null
    private var sportsJob: Job? = null

    init {
        loadHome()
        viewModelScope.launch { accounts.account.collect { account = it } }
        viewModelScope.launch { accounts.library.collect { saved = it.saved; history = it.history; favorites = it.favorites; searches = it.searches } }
    }

    fun loadHome() {
        homeJob?.cancel()
        homeJob = viewModelScope.launch {
            home = LoadState(home.data, loading = true)
            val shelves = listOf(Triple("TOP 10 Today", "trending/all/day", null),
                Triple("Popular movies", "movie/popular", MediaType.MOVIE), Triple("Series to get into", "tv/popular", MediaType.TV),
                Triple("Top rated", "movie/top_rated", MediaType.MOVIE))
            val results = shelves.map { (name, path, type) -> async {
                try { Result.success(Shelf(name, repository.catalog(path, type).items)) }
                catch (error: Exception) { coroutineContext.ensureActive(); Result.failure<Shelf>(error) }
            } }.awaitAll()
            home = LoadState(results.mapNotNull { it.getOrNull() }.takeIf { it.isNotEmpty() }, error =
                if (results.any { it.isFailure }) results.first { it.isFailure }.exceptionOrNull()?.localizedMessage else null)
        }
    }

    fun search(value: String) { query = value; loadCatalog(debounce = true) }
    fun rememberSearch() { accounts.rememberSearch(query) }
    fun clearSearches() { viewModelScope.launch { try { accounts.clearSearches() } catch (error: Exception) { coroutineContext.ensureActive(); accounts.showError(error) } } }
    fun refreshLocal() { history = store.history }
    fun filterCatalog(genre: Int = browseGenre, provider: Int = browseProvider) { browseGenre = genre; browseProvider = provider; loadCatalog() }
    fun browse(type: MediaType = browseType, sort: String = browseSort) {
        if (type != browseType) browseGenre = 0
        browseType = type; browseSort = sort; query = ""; loadCatalog()
    }
    fun loadCatalog(more: Boolean = false, debounce: Boolean = false) {
        if (more && (catalog.loading || (catalog.data?.page ?: 1) >= (catalog.data?.pages ?: 1))) return
        catalogJob?.cancel()
        val previous = if (more) catalog.data else null
        catalogJob = viewModelScope.launch {
            catalog = LoadState(previous, loading = true)
            if (debounce) delay(350)
            try {
                val text = query.trim()
                val filtered = browseGenre > 0 || browseProvider > 0
                val params = if (filtered) mapOf("with_genres" to browseGenre.takeIf { it > 0 }?.toString().orEmpty(),
                    "with_watch_providers" to browseProvider.takeIf { it > 0 }?.toString().orEmpty(), "watch_region" to "US",
                    "sort_by" to if (browseSort == "top_rated") "vote_average.desc" else "popularity.desc", "vote_count.gte" to "100") else emptyMap()
                val result = repository.catalog(if (text.isNotBlank()) "search/multi" else if (filtered) "discover/${browseType.path}" else "${browseType.path}/$browseSort",
                    if (text.isBlank()) browseType else null, (previous?.page ?: 0) + 1, text, params)
                catalog = LoadState(result.copy(items = ((previous?.items ?: emptyList()) + result.items).distinctBy { it.key }))
            } catch (error: Exception) { coroutineContext.ensureActive(); catalog = LoadState(previous, error = error.localizedMessage) }
        }
    }

    fun chooseLeague(value: League?) = chooseLeagues(value?.let { setOf(it) } ?: League.entries.toSet())
    fun chooseLeagues(values: Set<League>) {
        if (values.isEmpty()) return
        selectedLeagues = values.toSet()
        loadSports()
    }
    fun chooseDay(value: LocalDate) { day = value.coerceIn(LocalDate.now(), LocalDate.now().plusDays(13)); loadSports() }
    fun loadSports(refresh: Boolean = false) {
        sportsJob?.cancel()
        val requestedLeagues = selectedLeagues
        val requestedLeague = requestedLeagues.singleOrNull()
        val requestedDate = day
        sportsJob = viewModelScope.launch {
            sports = LoadState(if (refresh) sports.data else null, loading = true)
            try {
                if (requestedLeague != null) sports = LoadState(repository.schedule(requestedLeague, requestedDate))
                else {
                    val results = requestedLeagues.map { item -> async {
                        try { Result.success(repository.schedule(item, requestedDate)) }
                        catch (error: Exception) { coroutineContext.ensureActive(); Result.failure<Schedule>(error) }
                    } }.awaitAll()
                    if (results.all { it.isFailure }) throw results.first().exceptionOrNull()!!
                    sports = LoadState(Schedule(results.flatMap { it.getOrNull()?.games.orEmpty() }.sortedBy { it.date }, results.any { it.isFailure || it.getOrNull()?.partial == true }))
                }
            }
            catch (error: Exception) { coroutineContext.ensureActive(); sports = LoadState(sports.data, error = error.localizedMessage) }
        }
    }
    fun stopSportsRefresh() { sportsJob?.cancel(); sports = sports.copy(loading = false) }
    fun toggleSaved(media: Media) = accounts.toggleSaved(media)
    fun record(media: Media, season: Int = 1, episode: Int = 1) = accounts.record(media, season, episode)
    fun removeHistory(media: Media) = accounts.removeHistory(media)
    fun toggleTeam(league: League, team: Team) = accounts.toggleTeam(league, team)
    fun isFollowing(league: League, team: Team) = teamCloudKey(league, team.abbreviation) in favorites || "${league.name}:${team.id}" in favorites
    fun saveSettings(key: String, api: String, server: String) {
        store.tmdbKey = key; store.apiBase = api; store.serverId = server
        settingsRevision++; loadHome(); loadCatalog(); loadSports()
    }
}
