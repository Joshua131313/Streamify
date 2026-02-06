import { useSearchParams } from "react-router-dom";
import type { TMDBMedia } from "../../../types/TMDBMediaType"
import { MediaMetaBadges } from "../../ui/MediaMetaBadges/MediaMetaBadges";
import { TMDBImg } from "../../ui/TMDBImg/TMDBImg";
import { Container } from "../../layout/Container/Container";

interface Props {
    media: TMDBMedia;
}

export const YouAreWatching = ({media}: Props) => {
    console.log(media)
    const [searchParams] = useSearchParams();
    const season = searchParams.get("season");
    const episode = searchParams.get("episode");

    return (
        <>
        {/* <div className="you-are-watching-overlay"></div> */}
        <Container className="you-are-watching">
            <TMDBImg path={media.logo_path} type="logo" size="w500"/>
            <MediaMetaBadges date={media.date} vote_average={media.vote_average} genre_ids={media.genres?.map(g => g.id) ?? []} />
            {
                media.mediaType === "tv" && 
                <div className="episode-info">
                    <span>Season: {season}</span>
                    <span>Episode: {episode}</span>
                </div>
            }
            <div className="description">
                {media.overview}
            </div>
        </Container>
        </>
    )
}