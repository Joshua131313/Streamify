import "./MediaCard.css"
import { FaPlay } from "react-icons/fa";
import type { TMDBMedia } from "../../../types/TMDBMediaType";
import { Link } from "react-router-dom";
import { TMDBImg } from "../ImgProxy/TMDBImg";
import { Icon } from "../Icon/Icon";
import { usePlayUrl } from "../../../hooks/mediaHooks/usePlayUrl";

interface Props {
    media: TMDBMedia;
    className?: string;
}


export const ContinueWatchingCard = (props: Props) => {
    const { media, className } = props;

    const { url, season, episode } = usePlayUrl(media.id, media.mediaType);

    return (
        <Link to={url} className={`media-card continue-watching-card ${className}`}>
            <TMDBImg type="poster" size="w342" path={media.poster_path ?? ""} />
            <Icon Icon={FaPlay} />
            {
                media.mediaType === "tv" &&
                <div className="history-indicator">
                    S{season} E{episode}
                </div>
            }
        </Link>
    );
};