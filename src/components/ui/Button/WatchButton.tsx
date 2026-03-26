import { FaPlay } from "react-icons/fa"
import { Button } from "./Button"
import type { TMediaType } from "../../../types/tmdb";
import { Link, useNavigate } from "react-router-dom";
import { useLocalStorage } from "../../../hooks/utilHooks/useLocalStorage";
import { Icon } from "../Icon/Icon";
import type { TStreamProvider } from "../../../types/sports/sportsTypes";

interface Props {
    channel: string;
    variant?: "icon" | "button";
    className?: string;
    streamProvider: TStreamProvider;
    onContextMenu?: (e: any) => void;
    additionalParams?: string;
}
export const getWatchURL = ({
    streamProvider,
    channel,
    additionalParams = ""
}: { streamProvider: string, channel: string, additionalParams?: string }) => {
    return `?provider=${streamProvider}&channel=${channel}${additionalParams}`
}

export const WatchButton = (props: Props) => {
    const { channel, className, variant, streamProvider, onContextMenu, additionalParams = "" } = props;
    const navigate = useNavigate();
   
    return (
        <Link 
            onClick={() => navigate(getWatchURL({ channel, streamProvider, additionalParams }))} 
            onContextMenu={onContextMenu && onContextMenu}
            to={getWatchURL({
                channel,
                streamProvider,
                additionalParams
            })}
            className={`play-button watch-button ${className}`}>
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