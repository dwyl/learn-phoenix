export default ARIA;
declare namespace ARIA {
    function anyOf(instance: any, classes: any): any;
    function isFocusable(el: any, interactiveOnly: any): any;
    function attemptFocus(el: any, interactiveOnly: any): boolean;
    function focusFirstInteractive(el: any): boolean;
    function focusFirst(el: any): boolean;
    function focusLast(el: any): boolean;
}
