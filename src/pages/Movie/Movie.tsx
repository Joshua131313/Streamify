import { useParams } from "react-router-dom";
import { useMovie } from "../../hooks/mediaHooks/movieHooks/useMovie";
import { MediaLayout } from "../../components/layout/MediaLayout/MediaLayout";

const Movie = ()  => {
    const { movieId } = useParams();
    const { movie, isLoading, error } = useMovie({movieId: movieId!});


    return (
        <MediaLayout media={movie!} isLoading={isLoading} error={error} mediaType="movie">
            
        </MediaLayout>
    )
}
export default Movie;