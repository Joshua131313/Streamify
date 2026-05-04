import { FaPlay } from "react-icons/fa";
import { Button } from "./Button";
import type { TMediaType } from "../../../types/tmdb";
import { Link } from "react-router-dom";
import { Icon } from "../Icon/Icon";
import { usePlayUrl } from "../../../hooks/mediaHooks/usePlayUrl";

interface Props {
    mediaType: TMediaType;
    mediaId: number;
    variant?: "icon" | "button";
    className?: string;
}

export const PlayButton = (props: Props) => {
    const { mediaType, mediaId, variant = "button", className } = props;

    const { url, season, episode } = usePlayUrl(mediaId, mediaType);

    return (
        <Link to={url} className={`play-button ${className}`}>
            {variant === "button" ? (
                <Button className="play-button">
                    <FaPlay />
                    Play {mediaType === "tv" ? `| S${season} E${episode}` : ""}
                </Button>
            ) : (
                <Icon Icon={FaPlay} />
            )}
        </Link>
    );
};