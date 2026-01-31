import { BrowserRouter, Route, Routes } from "react-router-dom"
import { Home } from "../pages/Home/Home"
import { Movies } from "../pages/Movies/Movies"
import { Shows } from "../pages/Shows/Shows"
import { Movie } from "../pages/Movie/Movie"
import { Show } from "../pages/Show/Show"
import { AppLayout } from "../components/layout/AppLayout"

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
                </Route>
            </Routes>
        </BrowserRouter>
    )
}
