export default Browser;
declare namespace Browser {
    function canPushState(): boolean;
    function dropLocal(localStorage: any, namespace: any, subkey: any): any;
    function updateLocal(localStorage: any, namespace: any, subkey: any, initial: any, func: any): any;
    function getLocal(localStorage: any, namespace: any, subkey: any): any;
    function updateCurrentState(callback: any): void;
    function pushState(kind: any, meta: any, to: any): void;
    function setCookie(name: any, value: any, maxAgeSeconds: any): void;
    function getCookie(name: any): string;
    function deleteCookie(name: any): void;
    function redirect(toURL: any, flash: any, navigate?: (url: any) => void): void;
    function localKey(namespace: any, subkey: any): string;
    function getHashTargetEl(maybeHash: any): HTMLElement;
}
