import { FaWifi } from "react-icons/fa"
import "./OfflineScreen.css"

export const OfflineScreen = () => {

    return (
        <div className="offline-container">
            <FaWifi />
            <span>You are offline, try reconnecting to the internet...</span>
        </div>
    )
}