import "./SavedMedia.css"
import { useSavedMediaContext } from "../../context/SavedMediaContext";
import MediaLibraryLayout from "../../components/layout/MediaLayout/MediaLibraryLayout";

const SavedMedia = () => {

    const { savedMedia } = useSavedMediaContext();

    return (
        <MediaLibraryLayout
            title="Saved Media"
            subTitle="Browse all saved for later movies and TV shows"
            media={savedMedia}
        />
    )
}
export default SavedMedia;