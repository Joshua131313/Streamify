import { moviesSeries } from "../../../../data/movie-series"
import { MovieSeries } from "../../../media/MovieSeries/MovieSeries"
import "./MovieSeriesContainer.css"

export const MovieSeriesContainer = ({onlyFeatured} : {onlyFeatured: boolean}) => {
    const movieSeriesRow = moviesSeries.filter(x => onlyFeatured ? x.featured : true).map(movieSeriesID => {
        return (
            <MovieSeries movieSeriesID={movieSeriesID} />
        )
    })

    return (
        <div className="movie-series-container">
            {movieSeriesRow}
        </div>
    )
}