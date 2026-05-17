import "./MediaCard.css"
import { FaPlay } from "react-icons/fa";
import type { TMDBMedia } from "../../../types/TMDBMediaType";
import { Link } from "react-router-dom";
import { TMDBImg } from "../ImgProxy/TMDBImg";
import { Icon } from "../Icon/Icon";
import { usePlayUrl } from "../../../hooks/mediaHooks/usePlayUrl";
import { MediaCardInfo } from "./MediaCardInfo";
import { useApp } from "../../../context/AppContext";
import { Button } from "../Button/Button";
import { useWatchHistoryContext } from "../../../context/WatchHistoryContext";

interface Props {
    media: TMDBMedia;
    className?: string;
}


export const ContinueWatchingCard = (props: Props) => {
    const { media, className } = props;

    const { url, season, episode } = usePlayUrl(media.id, media.mediaType);
    const { removeHistory } = useWatchHistoryContext()
    const { isMobile } = useApp();

    return (
        <Link to={url} className={`${isMobile ? "mobile-media-card" : ""} media-card continue-watching-card ${className}`}>
            <div className="media-card-content">
                <TMDBImg type="backdrop" size="w780" path={isMobile ? media.poster_path : media.backdrop_path ?? ""} />
                <Icon Icon={FaPlay} />
            </div>
            {
                media.mediaType === "tv" &&
                <div className="history-indicator">
                    S{season} E{episode}
                </div>
            }

            <Button className="complete-button" onClick={() => removeHistory(media.id, media.mediaType)}>Completed</Button>
            <MediaCardInfo media={media} />
        </Link>
    );
};