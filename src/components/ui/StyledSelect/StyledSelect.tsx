import Select, {
  type Props as SelectProps,
  type GroupBase,
} from "react-select";
import "./StyledSelect.css"

const styles = {
  control: (base: any, state: any) => ({
    ...base,
    backgroundColor: "var(--bg-primary)",
    borderColor: "var(--border)",
    boxShadow: "none",
    minHeight: "40px",
    borderRadius: "var(--border-radius)",
    overflow: "hidden",
    "&:hover": {
      borderColor: "var(--border)",
    },
    zIndex: 100
  }),

  menu: (base: any) => ({
    ...base,
    backgroundColor: "var(--bg-surface)",
    borderRadius: "20px",
    overflow: "hidden",
    zIndex: 100,
  }),

  menuList: (base: any) => ({
    ...base,
    padding: 0,
  }),

  option: (base: any, state: any) => ({
    ...base,
    backgroundColor: state.isSelected
      ? "var(--accent-primary)"
      : state.isFocused
        ? "rgba(255, 255, 255, 0.08)"
        : "transparent",
    color:  state.isSelected ? "var(--bg-primary)" : "var(--text-primary)",
    cursor: "pointer",
    ":active": {
      backgroundColor: state.isSelected
        ? "var(--accent-primary)"
        : "rgba(255, 255, 255, 0.12)",
    },
        ":hover": {
      backgroundColor: state.isSelected ? "var(--accent-hover)" : "var(--bg-surface-hover)",
    },
  }),

  singleValue: (base: any) => ({
    ...base,
    color: "var(--text-primary)",
  }),

  indicatorSeparator: () => ({
    display: "none",
  }),

  placeholder: (base: any) => ({
    ...base,
    color: "var(--text-muted)",
  }),

  input: (base: any) => ({
    ...base,
    color: "var(--text-primary)",
  }),

  multiValue: (base: any) => ({
    ...base,
    backgroundColor: "rgba(220, 38, 38, 0.2)",
    borderRadius: "12px", // optional tweak for pills
    padding: "2px 4px",
  }),

  multiValueLabel: (base: any) => ({
    ...base,
    color: "var(--text-primary)",
    fontSize: "13px",
  }),

  multiValueRemove: (base: any) => ({
    ...base,
    color: "var(--accent-primary)",
    cursor: "pointer",
    ":hover": {
      backgroundColor: "var(--accent-primary)",
      color: "var(--bg-primary)",
    },
  }),
};
export function StyledSelect<
  Option,
  IsMulti extends boolean = false,
  Group extends GroupBase<Option> = GroupBase<Option>
>(props: SelectProps<Option, IsMulti, Group>) {
  return (
    <Select
      {...props}
      styles={styles}
      classNamePrefix="styled-select"
      className={`${props.className} app-select`}
    />
  );
}
