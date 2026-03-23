import { useSearchParams } from "react-router-dom";
import { getStreamURL } from "../../utils/sports/sportsUtils";
import { AppPlayer } from "../../components/ui/AppPlayer/AppPlayer";
import type { TStreamProvider } from "../../types/sports/sportsTypes";


export const SportsPlayer = () => {
    const [searchParams, setSearchParams] = useSearchParams();
    const provider = searchParams.get("provider");
    const channel = searchParams.get("channel");
    const cancelWatch = () => {
        searchParams.delete("provider");
        searchParams.delete("channel");
        setSearchParams(searchParams, { replace: true });
    }
    return (
        channel && provider ?
            <AppPlayer
                cancelPlay={cancelWatch}
                src={getStreamURL(provider as TStreamProvider, channel)}
            />
            : null
    )
}