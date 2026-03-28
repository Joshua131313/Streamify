import { FaThLarge } from "react-icons/fa";
import { Icon } from "../../components/ui/Icon/Icon";
import { Window } from "../../components/ui/Window/Window";
import { useMultiWatch } from "../../context/MultiWatchContext";
import { MultiWatchContent } from "./MultiWatchContent";
import { MultiWatchContentEmpty } from "./MultiWatchContentEmpty";

export const MultiWatch = () => {
    const { multiWatch } = useMultiWatch();

    return (
        <Window className="multi-watch" minimizedIcon={<Icon Icon={FaThLarge}/>} id="multiwatch" title="Multi Watch">
            {multiWatch.length === 0 ? (
                <MultiWatchContentEmpty />
            ) : (
                <MultiWatchContent />
            )}
        </Window>
    );
};