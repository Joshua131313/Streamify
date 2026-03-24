import { FaPlay } from "react-icons/fa"
import { Button } from "./Button"
import type { TMediaType } from "../../../types/tmdb";
import { Link } from "react-router-dom";
import { useLocalStorage } from "../../../hooks/utilHooks/useLocalStorage";
import { Icon } from "../Icon/Icon";
import type { TStreamProvider } from "../../../types/sports/sportsTypes";

interface Props {
    channel: string;
    variant?: "icon" | "button";
    className?: string;
    streamProvider: TStreamProvider;
    onContextMenu: (e: any) => void;
}
export const getWatchURL = ({
    streamProvider,
    channel
}: { streamProvider: string, channel: string }) => {
    return `?provider=${streamProvider}&channel=${channel}`
}

export const WatchButton = (props: Props) => {
    const { channel, className, variant, streamProvider, onContextMenu } = props;
    return (
        <Link onContextMenu={onContextMenu}
            to={getWatchURL({
                channel,
                streamProvider
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