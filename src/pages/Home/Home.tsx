import { HeroCarousel } from "../../components/ui/HeroCarousel/HeroCarousel"
import { MediaRail } from "../../components/media/MediaRail/MediaRail"
import "./Home.css"
import { RailsContainer } from "../../components/layout/Container/RailsContainer/RailsContainer"
import { MovieSeriesContainer } from "../../components/layout/Container/MovieSeriesContainer/MovieSeriesContainer"
import { useTMDBQuery } from "../../hooks/mediaHooks/tmdbHooks/useTMDBQuery"
import { SEO } from "../../components/SEO"

const Home = () => {

    return (
        <div className="home">
            <SEO 
                title="Home"
                description="Watch live sports streams on Streamify" 
            />
            <HeroCarousel />
            <RailsContainer />
            <MovieSeriesContainer onlyFeatured />
        </div>
    )
}
export default Home;