import { useSearchParams } from "react-router-dom";
import { useMediaLayoutContext } from "../../layout/MediaLayout/MediaLayoutContext";


export const YouAreWatching = () => {
    const [searchParams] = useSearchParams();
    const { media, mediaType } = useMediaLayoutContext();
    const season = searchParams.get("season");
    const episode = searchParams.get("episode");

    return (
        <aside className="you-are-watching" aria-label="Now watching">
            <span className="watching-caption">You are watching</span>
            <strong>{media.title}</strong>
            {
                mediaType === "tv" &&
                <div className="episode-info">
                    <span>Season {season || "1"}</span>
                    <span>Episode {episode || "1"}</span>
                </div>
            }
        </aside>
    )
}
