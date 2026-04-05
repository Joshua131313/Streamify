import { moviesSeries } from "../../../../data/movie-series"
import MovieSeries from "../../../media/MovieSeries/MovieSeries";
import "./MovieSeriesContainer.css"

export const MovieSeriesContainer = ({onlyFeatured, genre} : {onlyFeatured?: boolean, genre?: number}) => {
    const movieSeriesRow = moviesSeries.filter(x => {
        const genreFilter = genre ? x.genres.includes(genre) : true;
        if(onlyFeatured) {
            return x.featured && genreFilter
        }
        else {
            return genreFilter
        }
    }).map(movieSeriesID => {
        return (
            <MovieSeries key={movieSeriesID.id} movieSeriesID={movieSeriesID} />
        )
    })

    return (
        <div className="movie-series-container">
            {movieSeriesRow}
        </div>
    )
}