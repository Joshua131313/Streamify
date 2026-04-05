import { HeroCarousel } from "../../components/ui/HeroCarousel/HeroCarousel"
import "./Home.css"
import { RailsContainer } from "../../components/layout/Container/RailsContainer/RailsContainer"
import { MovieSeriesContainer } from "../../components/layout/Container/MovieSeriesContainer/MovieSeriesContainer"
import { useTMDBQuery } from "../../hooks/mediaHooks/tmdbHooks/useTMDBQuery"
import { SEO } from "../../components/SEO"
import { useInView } from "../../hooks/utilHooks/useInView"

const Home = () => {
    const movies = useInView({ rootMargin: "200px" });

    return (
        <div className="home">
            <SEO
                title="Home"
                description="Watch live sports streams on Streamify"
            />

            {/* Load immediately (above the fold) */}
            <HeroCarousel />

            {/* Load when near viewport */}
            <RailsContainer />

            <div ref={movies.ref}>
                {movies.isVisible ? (
                    <MovieSeriesContainer onlyFeatured />
                ) : (
                    <div style={{ height: 300 }} />
                )}
            </div>
        </div>
    );
};
export default Home;