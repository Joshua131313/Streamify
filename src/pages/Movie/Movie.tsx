import { useParams } from "react-router-dom";
import { useMovie } from "../../hooks/movieHooks/useMovie";
import { MediaLayout } from "../../components/layout/MediaLayout/MediaLayout";

export const Movie = ()  => {
    const { movieId } = useParams();
    const [movie, loading] = useMovie({movieId: movieId!});
    console.log("move", movie)

    if(loading || !movie) {
        return <div className="loading"></div>
    }

    return (
        <MediaLayout media={movie} mediaType="movie">
            <div className="he" style={{height: "90vh"}}></div>
            <iframe 
                style={{zIndex: 100}}
                src={`https://www.vidking.net/embed/movie/${movieId}`} 
                width="100%" 
                height="600" 
                >
            </iframe>
        </MediaLayout>
    )
}