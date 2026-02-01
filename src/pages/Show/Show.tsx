import { useParams } from "react-router-dom";
import { useShow } from "../../hooks/showHooks/useShow";
import { Trailer } from "../../components/ui/Trailer/Trailer";
import { MediaLayout } from "../../components/layout/MediaLayout/MediaLayout";

export const Show = ()  => {
    const { showId } = useParams();
    const [show, loading, err] = useShow({showId: showId!});
    console.log("move", show)
    
    return (
        <MediaLayout media={show!} err={err} loading={loading} mediaType="tv">

        </MediaLayout>
    )
}