import { FaPlay } from "react-icons/fa";
import { Button } from "./Button";
import type { TMediaType } from "../../../types/tmdb";
import { Link } from "react-router-dom";
import { Icon } from "../Icon/Icon";
import { useWatchHistoryContext } from "../../../context/WatchHistoryContext";

interface Props {
    mediaType: TMediaType;
    mediaId: number;
    variant?: "icon" | "button";
    className?: string;
}

export const PlayButton = (props: Props) => {
    const { mediaType, mediaId, variant = "button", className } = props;

    const { getHistoryItem } = useWatchHistoryContext();

    const playUrl = () => {
        const base = `/${mediaType}/${mediaId}?play`;

        if (mediaType === "movie") {
            return base;
        }

        const history = getHistoryItem(mediaId, "tv");

        const season = history?.season ?? 1;
        const episode = history?.episode ?? 1;

        return `${base}&season=${season}&episode=${episode}`;
    };

    return (
        <Link to={playUrl()} className={`play-button ${className}`}>
            {variant === "button" ? (
                <Button className="play-button">
                    <FaPlay />
                    Play
                </Button>
            ) : (
                <Icon Icon={FaPlay} />
            )}
        </Link>
    );
};