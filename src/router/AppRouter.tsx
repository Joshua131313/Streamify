import { BrowserRouter, Route, Routes } from "react-router-dom"
import { Home } from "../pages/Home/Home"
import { Movies } from "../pages/Movies/Movies"
import { Shows } from "../pages/Shows/Shows"
import { Movie } from "../pages/Movie/Movie"
import { Show } from "../pages/Show/Show"
import { AppLayout } from "../components/layout/AppLayout"
import { Search } from "../pages/Search/Search"
import { Browse } from "../pages/Browse/Browse"
import { SavedMedia } from "../pages/SavedMedia/SavedMedia"

export const AppRouter = () => {

    return  (
        <BrowserRouter>
            <Routes>
                <Route element={<AppLayout />}>
                    <Route path="" element={<Home />}/>
                    <Route path="movies" element={<Movies />} />
                    <Route path="movie/:movieId" element={<Movie />} />
                    <Route path="tv-shows" element={<Shows />} />
                    <Route path="tv/:showId" element={<Show />} />
                    <Route path="search" element={<Search />}/>
                    <Route path="discover" element={<Browse />}/>
                    <Route path="saved" element={<SavedMedia />}/>
                </Route>
            </Routes>
        </BrowserRouter>
    )
}
