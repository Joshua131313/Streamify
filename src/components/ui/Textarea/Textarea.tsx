import {
    useRef,
    useEffect,
    type TextareaHTMLAttributes,
} from "react";
import type { IconType } from "react-icons";
import "./Textarea.css";

interface Props extends TextareaHTMLAttributes<HTMLTextAreaElement> {
    Icon?: IconType;
    error?: string;
    maxHeight?: number;
}

export const Textarea = ({
    Icon,
    error,
    maxHeight = 150,
    ...props
}: Props) => {
    const ref = useRef<HTMLTextAreaElement>(null);

    const resize = () => {
        const el = ref.current;
        if (!el) return;

        el.style.height = "auto";

        const newHeight = Math.min(el.scrollHeight, maxHeight);
        el.style.height = newHeight + "px";

        el.style.overflowY =
            el.scrollHeight > maxHeight ? "auto" : "hidden";
    };

    useEffect(() => {
        resize();
    }, [props.value]);

    return (
        <div className={`textarea-container ${Icon ? "has-icon" : ""}`}>
            {Icon && <Icon className="icon" />}
            <textarea
                ref={ref}
                {...props}
                rows={1}
                onInput={resize}
            />
            {error && <span className="error">{error}</span>}
        </div>
    );
};