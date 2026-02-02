import { providers } from "../../../data/providers";
import { AccentLine } from "../../ui/AccentLine/AccentLine";
import { useMediaRail } from "./MediaRailContext"
import { MediaRailTabs } from "./MediaRailTabs"

export const MediaRailHeader = () => {
    const { title, category, provider, variant } = useMediaRail();
    return (
        <div className="rail-header flex-row sb">
            {
                variant === "top10" ?
                <div className="top10-title">
                    TOP10
                </div>
                :
                <div className="flex-row">
                    <AccentLine />
                    <h2>
                    {title}                 
                    {
                        category === "provider" && <span>{providers.find(x => x.provider === provider)?.name}</span>
                    }
                    </h2>

                </div>
            }
            <MediaRailTabs />
        </div>
    )
}