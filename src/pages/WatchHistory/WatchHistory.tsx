import { useWatchHistoryContext } from "../../context/WatchHistoryContext";
import "./WatchHistory.css"
import MediaLibraryLayout from "../../components/layout/MediaLayout/MediaLibraryLayout";

const WatchHistory = () => {

    const { historyMedia } = useWatchHistoryContext();

    return (
        <MediaLibraryLayout
            title="Continue Watching"
            subTitle=""
            media={historyMedia}
        />
    )
}
export default WatchHistory;