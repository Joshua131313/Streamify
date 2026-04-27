import { createPortal } from "react-dom"
import "./Model.css"

interface Props {
    children: React.ReactNode;
    open: boolean;
    onClose: () => void;
}

export const Model = (props: Props) => {
    const { children, open, onClose } = props;

    if(!open) return null;

    return createPortal(
        <>
        <div className="model">
            {children}
        </div>
        <div className="model-overlay" onClick={onClose} />
        </>
    , document.body)
}