import { useParams } from "react-router-dom";
import { useMovie } from "../../hooks/movieHooks/useMovie";
import { MediaLayout } from "../../components/layout/MediaLayout/MediaLayout";

export const Movie = ()  => {
    const { movieId } = useParams();
    const [movie, loading, err] = useMovie({movieId: movieId!});
    console.log("move", movie)


    return (
        <MediaLayout media={movie!} loading={loading} err={err} mediaType="movie">

        </MediaLayout>
    )
}