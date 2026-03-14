import { FaPlay } from "react-icons/fa"
import { Button } from "./Button"
import type { TMediaType } from "../../../types/tmdb";
import { Link } from "react-router-dom";
import { useLocalStorage } from "../../../hooks/utilHooks/useLocalStorage";
import { Icon } from "../Icon/Icon";

interface Props {
    mediaType: TMediaType;
    mediaId: number;
    variant?: "icon" | "button";
    className?: string;
}

export const PlayButton = (props : Props) => {
    const { mediaType, mediaId, variant = "button", className } = props;
    const { get } = useLocalStorage();
    
    const playUrl = () => {
        const base = `/${mediaType}/${mediaId}?play`
        if(mediaType === "movie") {
            return base;
        }
        else {
            const lastEpisode = get(mediaId.toString(), {season: 1, episode: 1});
            return base + `&season=${lastEpisode.season}&episode=${lastEpisode.episode}`
        }
    }

    return (
        <Link to={playUrl()} className={`play-button ${className}`}>
            {variant === "button" ?
                <Button className="play-button">
                    <FaPlay />
                    Play
                </Button>
                :
                <Icon 
                    Icon={FaPlay}
                />
            }
        </Link>
    )
}