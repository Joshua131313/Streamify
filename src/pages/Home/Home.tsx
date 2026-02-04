import { HeroCarousel } from "../../components/ui/HeroCarousel/HeroCarousel"
import { MediaRail } from "../../components/media/MediaRail/MediaRail"
import "./Home.css"
import { RailsContainer } from "../../components/layout/Container/RailsContainer/RailsContainer"
import { MovieSeriesContainer } from "../../components/layout/Container/MovieSeriesContainer/MovieSeriesContainer"
import { useTMDBQuery } from "../../hooks/mediaHooks/tmdbHooks/useTMDBQuery"

export const Home = ()  => {

    return (
        <div className="home">
            <HeroCarousel />
            <RailsContainer />
            <MovieSeriesContainer onlyFeatured/>
        </div>
    )
}