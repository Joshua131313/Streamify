import { FaPlay } from "react-icons/fa"
import { Button } from "./Button"
import type { TMediaType } from "../../../types/tmdb";
import { Link } from "react-router-dom";
import { useLocalStorage } from "../../../hooks/utilHooks/useLocalStorage";
import { Icon } from "../Icon/Icon";
import type { TStreamProvider } from "../../../types/sports";

interface Props {
    channel: number;
    variant?: "icon" | "button";
    className?: string;
    streamProvider: TStreamProvider;
}

export const WatchButton = (props : Props) => {
    const { channel, className, variant, streamProvider } = props;
    const { get } = useLocalStorage();
    
    const watch = () => {
        return `?provider=${streamProvider}&channel=${channel}`
    }

    return (
        <Link to={watch()} className={`play-button watch-button ${className}`}>
            {variant === "button" ?
                <Button className="play-button">
                    <FaPlay />
                    Watch
                </Button>
                :
                <Icon 
                    Icon={FaPlay}
                />
            }
        </Link>
    )
}