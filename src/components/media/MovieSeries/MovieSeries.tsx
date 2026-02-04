import type { TMovieSeriesID } from "../../../data/movie-series";
import { useMovieCollection } from "../../../hooks/mediaHooks/movieHooks/useMovieColllection";
import { useTMDBQuery } from "../../../hooks/mediaHooks/tmdbHooks/useTMDBQuery";
import { Container } from "../../layout/Container/Container"
import { MediaCard } from "../../ui/MediaCard/MediaCard";
import { TMDBImg } from "../../ui/TMDBImg/TMDBImg";
import "./MovieSeries.css"

interface Props {
    movieSeriesID: TMovieSeriesID;
}

export const MovieSeries = (props: Props) => {
    const { movieSeriesID } = props;
    const { movies, seriesBackdropPath, seriesPosterPath } = useMovieCollection(movieSeriesID.id);
    const moviesRow = movies.map(movie => {
        return (
            <MediaCard media={movie} key={movie.id}/>
        )
    })
    return (
        <Container className="movie-series media-grid" title={movieSeriesID.name}>
            {/* <TMDBImg 
                path={seriesBackdropPath}
            /> */}
            {moviesRow}
        </Container>
    )
}