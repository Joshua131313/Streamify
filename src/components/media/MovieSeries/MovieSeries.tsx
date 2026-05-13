import React from "react";
import type { TMovieSeriesID } from "../../../data/movie-series";
import { useMovieCollection } from "../../../hooks/mediaHooks/movieHooks/useMovieColllection";
import { useTMDBQuery } from "../../../hooks/mediaHooks/tmdbHooks/useTMDBQuery";
import { Container } from "../../layout/Container/Container"
import { MediaCard } from "../../ui/MediaCard/MediaCard";
import { TMDBImg } from "../../ui/ImgProxy/TMDBImg";
import "./MovieSeries.css"
import { MediaSkeletonCard } from "../../ui/MediaCard/SkeletonCards/MediaSkeletonCard";

interface Props {
    movieSeriesID: TMovieSeriesID;
}

const MovieSeries = (props: Props) => {
    const { movieSeriesID } = props;
    const { movies, seriesBackdropPath, seriesPosterPath, isLoading } = useMovieCollection(movieSeriesID.id);
    const moviesRow = movies.map(movie => {
       if(isLoading) {
        return <MediaSkeletonCard />
       }
       else {
         return (
            <MediaCard media={movie} key={movie.id} />
        )
       }
    })
    return (
        <Container className="movie-series media-grid" title={movieSeriesID.name} backdropImg={movieSeriesID.backdrop}>
            {/* <TMDBImg 
                path={seriesBackdropPath}
            /> */}
            {moviesRow}
        </Container>
    )
}
export default React.memo(MovieSeries);