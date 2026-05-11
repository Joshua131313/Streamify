import "./MediaCard.css"
import { FaPlay } from "react-icons/fa";
import type { TMDBMedia } from "../../../types/TMDBMediaType";
import { Link } from "react-router-dom";
import { TMDBImg } from "../ImgProxy/TMDBImg";
import { Icon } from "../Icon/Icon";
import { usePlayUrl } from "../../../hooks/mediaHooks/usePlayUrl";
import { MediaCardInfo } from "./MediaCardInfo";

interface Props {
    media: TMDBMedia;
    className?: string;
}


export const ContinueWatchingCard = (props: Props) => {
    const { media, className } = props;

    const { url, season, episode } = usePlayUrl(media.id, media.mediaType);

    return (
        <Link to={url} className={`media-card continue-watching-card ${className}`}>
            <div>
                <TMDBImg type="backdrop" size="w780" path={media.backdrop_path ?? ""} />
            <Icon Icon={FaPlay} />
            </div>
            {
                media.mediaType === "tv" &&
                <div className="history-indicator">
                    S{season} E{episode}
                </div>
            }
            <MediaCardInfo media={media} />
        </Link>
    );
};