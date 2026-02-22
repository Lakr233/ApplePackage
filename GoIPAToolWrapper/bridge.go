package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	stdhttp "net/http"
	"net/url"
	"os"
	"runtime/debug"
	"sort"
	"strings"
	"sync"
	"time"
	"unsafe"

	"github.com/majd/ipatool/v2/pkg/appstore"
	iphttp "github.com/majd/ipatool/v2/pkg/http"
	"github.com/majd/ipatool/v2/pkg/keychain"
	"github.com/majd/ipatool/v2/pkg/util/machine"
	"github.com/majd/ipatool/v2/pkg/util/operatingsystem"
	"howett.net/plist"
)

const (
	defaultUserAgent      = "Configurator/2.17 (Macintosh; OS X 15.2; 24C5089c) AppleWebKit/0620.1.16.11.6"
	authCodeRequiredError = "Authentication requires verification code\nIf no verification code prompted, try logging in at https://account.apple.com to trigger the alert and fill the code in the 2FA Code here."
)

type envelope struct {
	OK     bool        `json:"ok"`
	Result interface{} `json:"result,omitempty"`
	Error  string      `json:"error,omitempty"`
}

type searchRequest struct {
	Term        string `json:"term"`
	CountryCode string `json:"countryCode"`
	Limit       int    `json:"limit"`
	EntityType  string `json:"entityType"`
}

type lookupRequest struct {
	BundleID    string `json:"bundleID"`
	CountryCode string `json:"countryCode"`
}

type bagRequest struct {
	DeviceIdentifier string `json:"deviceIdentifier"`
	UserAgent        string `json:"userAgent"`
}

type authenticateRequest struct {
	Email            string        `json:"email"`
	Password         string        `json:"password"`
	Code             string        `json:"code"`
	Cookies          []swiftCookie `json:"cookies"`
	DeviceIdentifier string        `json:"deviceIdentifier"`
	UserAgent        string        `json:"userAgent"`
}

type purchaseRequest struct {
	Account          swiftAccount  `json:"account"`
	App              swiftSoftware `json:"app"`
	DeviceIdentifier string        `json:"deviceIdentifier"`
	UserAgent        string        `json:"userAgent"`
}

type listVersionsRequest struct {
	Account          swiftAccount `json:"account"`
	BundleIdentifier string       `json:"bundleIdentifier"`
	DeviceIdentifier string       `json:"deviceIdentifier"`
	UserAgent        string       `json:"userAgent"`
}

type versionMetadataRequest struct {
	Account          swiftAccount  `json:"account"`
	App              swiftSoftware `json:"app"`
	VersionID        string        `json:"versionID"`
	DeviceIdentifier string        `json:"deviceIdentifier"`
	UserAgent        string        `json:"userAgent"`
}

type downloadRequest struct {
	Account           swiftAccount  `json:"account"`
	App               swiftSoftware `json:"app"`
	ExternalVersionID string        `json:"externalVersionID"`
	DeviceIdentifier  string        `json:"deviceIdentifier"`
	UserAgent         string        `json:"userAgent"`
}

type swiftCookie struct {
	Name      string   `json:"name"`
	Value     string   `json:"value"`
	Path      string   `json:"path"`
	Domain    *string  `json:"domain,omitempty"`
	ExpiresAt *float64 `json:"expiresAt,omitempty"`
	HTTPOnly  bool     `json:"httpOnly"`
	Secure    bool     `json:"secure"`
}

type swiftAccount struct {
	Email                       string        `json:"email"`
	Password                    string        `json:"password"`
	AppleID                     string        `json:"appleId"`
	Store                       string        `json:"store"`
	FirstName                   string        `json:"firstName"`
	LastName                    string        `json:"lastName"`
	PasswordToken               string        `json:"passwordToken"`
	DirectoryServicesIdentifier string        `json:"directoryServicesIdentifier"`
	Cookie                      []swiftCookie `json:"cookie"`
	Pod                         *string       `json:"pod,omitempty"`
}

type swiftSoftware struct {
	ID       int64    `json:"trackId"`
	BundleID string   `json:"bundleId"`
	Name     string   `json:"trackName"`
	Version  string   `json:"version"`
	Price    *float64 `json:"price,omitempty"`
}

type bagResult struct {
	AuthEndpoint string `json:"authEndpoint"`
}

type purchaseResult struct {
	Account swiftAccount `json:"account"`
}

type listVersionsResult struct {
	Account  swiftAccount `json:"account"`
	Versions []string     `json:"versions"`
}

type versionMetadataResult struct {
	Account  swiftAccount       `json:"account"`
	Metadata versionMetadataDTO `json:"metadata"`
}

type downloadResult struct {
	Account                  swiftAccount   `json:"account"`
	DownloadURL              string         `json:"downloadURL"`
	Sinfs                    []downloadSinf `json:"sinfs"`
	BundleShortVersionString string         `json:"bundleShortVersionString"`
	BundleVersion            string         `json:"bundleVersion"`
	ITunesMetadataBase64     string         `json:"iTunesMetadataBase64"`
}

type downloadSinf struct {
	ID         int64  `json:"id"`
	SinfBase64 string `json:"sinfBase64"`
}

type versionMetadataDTO struct {
	DisplayVersion string    `json:"displayVersion"`
	ReleaseDate    time.Time `json:"releaseDate"`
}

type appStoreContext struct {
	client    appstore.AppStore
	cookieJar *memoryCookieJar
}

func main() {}

//export APGoIPAToolVersion
func APGoIPAToolVersion() *C.char {
	result := map[string]string{
		"module":  "github.com/majd/ipatool/v2",
		"version": ipatoolVersion(),
	}
	return respondSuccess(result)
}

func ipatoolVersion() string {
	buildInfo, ok := debug.ReadBuildInfo()
	if !ok {
		return "unknown"
	}

	for _, dep := range buildInfo.Deps {
		if dep.Path == "github.com/majd/ipatool/v2" {
			return dep.Version
		}
	}
	return "unknown"
}

//export APGoIPAToolSearch
func APGoIPAToolSearch(requestJSON *C.char) *C.char {
	var request searchRequest
	if err := decodeRequest(requestJSON, &request); err != nil {
		return respondError(err)
	}

	results, err := performSearch(request)
	if err != nil {
		return respondError(err)
	}

	return respondSuccess(results)
}

//export APGoIPAToolLookup
func APGoIPAToolLookup(requestJSON *C.char) *C.char {
	var request lookupRequest
	if err := decodeRequest(requestJSON, &request); err != nil {
		return respondError(err)
	}

	result, err := performLookup(request)
	if err != nil {
		return respondError(err)
	}

	return respondSuccess(result)
}

//export APGoIPAToolFetchBag
func APGoIPAToolFetchBag(requestJSON *C.char) *C.char {
	var request bagRequest
	if err := decodeRequest(requestJSON, &request); err != nil {
		return respondError(err)
	}

	context, err := newAppStoreContext(request.DeviceIdentifier, nil)
	if err != nil {
		return respondError(err)
	}

	output, err := context.client.Bag(appstore.BagInput{})
	if err != nil {
		return respondError(normalizeError(err))
	}

	return respondSuccess(bagResult{AuthEndpoint: output.AuthEndpoint})
}

//export APGoIPAToolAuthenticate
func APGoIPAToolAuthenticate(requestJSON *C.char) *C.char {
	var request authenticateRequest
	if err := decodeRequest(requestJSON, &request); err != nil {
		return respondError(err)
	}

	context, err := newAppStoreContext(request.DeviceIdentifier, request.Cookies)
	if err != nil {
		return respondError(err)
	}

	bagOutput, err := context.client.Bag(appstore.BagInput{})
	if err != nil {
		return respondError(normalizeError(err))
	}

	output, err := context.client.Login(appstore.LoginInput{
		Email:    request.Email,
		Password: request.Password,
		AuthCode: request.Code,
		Endpoint: bagOutput.AuthEndpoint,
	})
	if err != nil {
		return respondError(normalizeError(err))
	}

	account := mapAccountFromIpatool(output.Account, request.Password, context.cookieJar.Export())
	if account.Email == "" {
		account.Email = request.Email
	}
	if account.Password == "" {
		account.Password = request.Password
	}

	return respondSuccess(account)
}

//export APGoIPAToolPurchase
func APGoIPAToolPurchase(requestJSON *C.char) *C.char {
	var request purchaseRequest
	if err := decodeRequest(requestJSON, &request); err != nil {
		return respondError(err)
	}

	context, err := newAppStoreContext(request.DeviceIdentifier, request.Account.Cookie)
	if err != nil {
		return respondError(err)
	}

	inputAccount := mapAccountToIpatool(request.Account)
	if err := context.client.Purchase(appstore.PurchaseInput{
		Account: inputAccount,
		App:     mapSoftwareToIpatool(request.App),
	}); err != nil {
		return respondError(normalizeError(err))
	}

	updated := request.Account
	updated.Cookie = context.cookieJar.Export()
	if inputAccount.Pod != "" {
		pod := inputAccount.Pod
		updated.Pod = &pod
	}

	return respondSuccess(purchaseResult{Account: updated})
}

//export APGoIPAToolListVersions
func APGoIPAToolListVersions(requestJSON *C.char) *C.char {
	var request listVersionsRequest
	if err := decodeRequest(requestJSON, &request); err != nil {
		return respondError(err)
	}

	context, err := newAppStoreContext(request.DeviceIdentifier, request.Account.Cookie)
	if err != nil {
		return respondError(err)
	}

	inputAccount := mapAccountToIpatool(request.Account)
	lookupOutput, err := context.client.Lookup(appstore.LookupInput{
		Account:  inputAccount,
		BundleID: request.BundleIdentifier,
	})
	if err != nil {
		return respondError(normalizeError(err))
	}

	versionOutput, err := context.client.ListVersions(appstore.ListVersionsInput{
		Account: inputAccount,
		App:     lookupOutput.App,
	})
	if err != nil {
		return respondError(normalizeError(err))
	}

	updated := request.Account
	updated.Cookie = context.cookieJar.Export()
	result := listVersionsResult{
		Account:  updated,
		Versions: append([]string(nil), versionOutput.ExternalVersionIdentifiers...),
	}

	return respondSuccess(result)
}

//export APGoIPAToolGetVersionMetadata
func APGoIPAToolGetVersionMetadata(requestJSON *C.char) *C.char {
	var request versionMetadataRequest
	if err := decodeRequest(requestJSON, &request); err != nil {
		return respondError(err)
	}

	context, err := newAppStoreContext(request.DeviceIdentifier, request.Account.Cookie)
	if err != nil {
		return respondError(err)
	}

	inputAccount := mapAccountToIpatool(request.Account)
	metadataOutput, err := context.client.GetVersionMetadata(appstore.GetVersionMetadataInput{
		Account:   inputAccount,
		App:       mapSoftwareToIpatool(request.App),
		VersionID: request.VersionID,
	})
	if err != nil {
		return respondError(normalizeError(err))
	}

	updated := request.Account
	updated.Cookie = context.cookieJar.Export()
	result := versionMetadataResult{
		Account: updated,
		Metadata: versionMetadataDTO{
			DisplayVersion: metadataOutput.DisplayVersion,
			ReleaseDate:    metadataOutput.ReleaseDate,
		},
	}

	return respondSuccess(result)
}

//export APGoIPAToolDownload
func APGoIPAToolDownload(requestJSON *C.char) *C.char {
	var request downloadRequest
	if err := decodeRequest(requestJSON, &request); err != nil {
		return respondError(err)
	}

	result, err := performDownload(request)
	if err != nil {
		return respondError(normalizeError(err))
	}

	return respondSuccess(result)
}

//export APGoIPAToolFreeString
func APGoIPAToolFreeString(value *C.char) {
	if value == nil {
		return
	}
	C.free(unsafe.Pointer(value))
}

func performSearch(request searchRequest) ([]json.RawMessage, error) {
	entityValue := "software"
	if strings.EqualFold(request.EntityType, "ipad") {
		entityValue = "iPadSoftware"
	}

	query := url.Values{}
	query.Set("entity", entityValue)
	query.Set("limit", fmt.Sprintf("%d", request.Limit))
	query.Set("media", "software")
	query.Set("term", request.Term)
	query.Set("country", request.CountryCode)

	endpoint := "https://itunes.apple.com/search?" + query.Encode()
	body, err := executeJSONRequest(endpoint, defaultUserAgent)
	if err != nil {
		return nil, err
	}

	var decoded struct {
		Results []json.RawMessage `json:"results"`
	}
	if err := json.Unmarshal(body, &decoded); err != nil {
		return nil, fmt.Errorf("failed to decode search response: %w", err)
	}

	return decoded.Results, nil
}

func performLookup(request lookupRequest) (json.RawMessage, error) {
	query := url.Values{}
	query.Set("bundleId", request.BundleID)
	query.Set("country", request.CountryCode)
	query.Set("entity", "software,iPadSoftware")
	query.Set("limit", "1")
	query.Set("media", "software")

	endpoint := "https://itunes.apple.com/lookup?" + query.Encode()
	body, err := executeJSONRequest(endpoint, defaultUserAgent)
	if err != nil {
		return nil, err
	}

	var decoded struct {
		ResultCount int               `json:"resultCount"`
		Results     []json.RawMessage `json:"results"`
	}
	if err := json.Unmarshal(body, &decoded); err != nil {
		return nil, fmt.Errorf("failed to decode lookup response: %w", err)
	}
	if decoded.ResultCount == 0 || len(decoded.Results) == 0 {
		return nil, errors.New("no results found")
	}

	return decoded.Results[0], nil
}

func performDownload(request downloadRequest) (downloadResult, error) {
	context, err := newAppStoreContext(request.DeviceIdentifier, request.Account.Cookie)
	if err != nil {
		return downloadResult{}, err
	}

	account := mapAccountToIpatool(request.Account)
	payload := map[string]interface{}{
		"creditDisplay": "",
		"guid":          strings.TrimSpace(request.DeviceIdentifier),
		"salableAdamId": request.App.ID,
	}
	if strings.TrimSpace(request.ExternalVersionID) != "" {
		payload["externalVersionId"] = strings.TrimSpace(request.ExternalVersionID)
	}

	headers := map[string]string{
		"Content-Type": "application/x-apple-plist",
		"User-Agent":   userAgentOrDefault(request.UserAgent),
		"iCloud-DSID":  request.Account.DirectoryServicesIdentifier,
		"X-Dsid":       request.Account.DirectoryServicesIdentifier,
	}

	client := iphttp.NewClient[map[string]interface{}](iphttp.Args{
		CookieJar: context.cookieJar,
	})
	response, err := client.Send(iphttp.Request{
		Method:         iphttp.MethodPOST,
		URL:            fmt.Sprintf("https://%s/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct", storeAPIHost(account.Pod)),
		Headers:        headers,
		Payload:        &iphttp.XMLPayload{Content: payload},
		ResponseFormat: iphttp.ResponseFormatXML,
	})
	if err != nil {
		return downloadResult{}, fmt.Errorf("request failed: %w", err)
	}

	data := response.Data
	if failureType := asString(data["failureType"]); failureType != "" {
		customerMessage := asString(data["customerMessage"])
		switch failureType {
		case "2034", "2042":
			return downloadResult{}, errors.New("password token is expired")
		case "9610":
			return downloadResult{}, errors.New("License required")
		default:
			if customerMessage != "" {
				return downloadResult{}, errors.New(customerMessage)
			}
			return downloadResult{}, fmt.Errorf("download failed: %s", failureType)
		}
	}

	items, ok := data["songList"].([]interface{})
	if !ok || len(items) == 0 {
		return downloadResult{}, errors.New("no items in response")
	}

	item, ok := items[0].(map[string]interface{})
	if !ok {
		return downloadResult{}, errors.New("invalid response")
	}

	downloadURL := asString(item["URL"])
	if downloadURL == "" {
		return downloadResult{}, errors.New("missing download URL")
	}

	metadata, ok := item["metadata"].(map[string]interface{})
	if !ok {
		return downloadResult{}, errors.New("missing metadata")
	}

	bundleShortVersionString := asString(metadata["bundleShortVersionString"])
	bundleVersion := asString(metadata["bundleVersion"])
	if bundleShortVersionString == "" || bundleVersion == "" {
		return downloadResult{}, errors.New("missing required information")
	}

	metadata["apple-id"] = request.Account.Email
	metadata["userName"] = request.Account.Email

	itunesMetadata, err := plist.Marshal(metadata, plist.BinaryFormat)
	if err != nil {
		return downloadResult{}, fmt.Errorf("failed to encode iTunesMetadata: %w", err)
	}

	rawSinfs, ok := item["sinfs"].([]interface{})
	if !ok || len(rawSinfs) == 0 {
		return downloadResult{}, errors.New("no sinf found in response")
	}

	sinfs := make([]downloadSinf, 0, len(rawSinfs))
	for _, entry := range rawSinfs {
		sinfMap, ok := entry.(map[string]interface{})
		if !ok {
			return downloadResult{}, errors.New("invalid sinf item")
		}

		id, ok := asInt64(sinfMap["id"])
		if !ok {
			return downloadResult{}, errors.New("invalid sinf item")
		}

		rawData, ok := asBytes(sinfMap["sinf"])
		if !ok {
			return downloadResult{}, errors.New("invalid sinf item")
		}

		sinfs = append(sinfs, downloadSinf{
			ID:         id,
			SinfBase64: base64.StdEncoding.EncodeToString(rawData),
		})
	}

	updated := request.Account
	updated.Cookie = context.cookieJar.Export()
	if account.Pod != "" {
		pod := account.Pod
		updated.Pod = &pod
	}

	return downloadResult{
		Account:                  updated,
		DownloadURL:              downloadURL,
		Sinfs:                    sinfs,
		BundleShortVersionString: bundleShortVersionString,
		BundleVersion:            bundleVersion,
		ITunesMetadataBase64:     base64.StdEncoding.EncodeToString(itunesMetadata),
	}, nil
}

func executeJSONRequest(endpoint, userAgent string) ([]byte, error) {
	if strings.TrimSpace(userAgent) == "" {
		userAgent = defaultUserAgent
	}

	req, err := stdhttp.NewRequest(stdhttp.MethodGet, endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("User-Agent", userAgent)

	client := &stdhttp.Client{Timeout: 30 * time.Second}
	res, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer res.Body.Close()

	if res.StatusCode != stdhttp.StatusOK {
		return nil, fmt.Errorf("request failed with status %d", res.StatusCode)
	}

	body, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	return body, nil
}

func newAppStoreContext(deviceIdentifier string, cookies []swiftCookie) (*appStoreContext, error) {
	guid := strings.TrimSpace(deviceIdentifier)
	if guid == "" {
		return nil, errors.New("device identifier is empty")
	}

	cookieJar := newMemoryCookieJar()
	cookieJar.Import(cookies)

	store := appstore.NewAppStore(appstore.Args{
		Keychain:        newMemoryKeychain(),
		CookieJar:       cookieJar,
		OperatingSystem: operatingsystem.New(),
		Machine: fixedMachine{
			guid: guid,
		},
	})

	return &appStoreContext{
		client:    store,
		cookieJar: cookieJar,
	}, nil
}

func mapAccountToIpatool(input swiftAccount) appstore.Account {
	storeFront := strings.TrimSpace(input.Store)
	if storeFront != "" && !strings.Contains(storeFront, "-") {
		storeFront += "-1"
	}

	pod := ""
	if input.Pod != nil {
		pod = strings.TrimSpace(*input.Pod)
	}

	return appstore.Account{
		Email:               input.Email,
		PasswordToken:       input.PasswordToken,
		DirectoryServicesID: input.DirectoryServicesIdentifier,
		Name:                strings.TrimSpace(strings.Join([]string{input.FirstName, input.LastName}, " ")),
		StoreFront:          storeFront,
		Password:            input.Password,
		Pod:                 pod,
	}
}

func mapAccountFromIpatool(input appstore.Account, password string, cookies []swiftCookie) swiftAccount {
	firstName, lastName := splitName(input.Name)
	store := input.StoreFront
	if parts := strings.SplitN(store, "-", 2); len(parts) > 0 {
		store = parts[0]
	}

	var pod *string
	if input.Pod != "" {
		value := input.Pod
		pod = &value
	}

	return swiftAccount{
		Email:                       input.Email,
		Password:                    password,
		AppleID:                     input.Email,
		Store:                       store,
		FirstName:                   firstName,
		LastName:                    lastName,
		PasswordToken:               input.PasswordToken,
		DirectoryServicesIdentifier: input.DirectoryServicesID,
		Cookie:                      cookies,
		Pod:                         pod,
	}
}

func mapSoftwareToIpatool(input swiftSoftware) appstore.App {
	price := 0.0
	if input.Price != nil {
		price = *input.Price
	}
	return appstore.App{
		ID:       input.ID,
		BundleID: input.BundleID,
		Name:     input.Name,
		Version:  input.Version,
		Price:    price,
	}
}

func storeAPIHost(pod string) string {
	pod = strings.TrimSpace(pod)
	if pod == "" {
		return "p25-buy.itunes.apple.com"
	}
	return "p" + pod + "-buy.itunes.apple.com"
}

func userAgentOrDefault(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return defaultUserAgent
	}
	return value
}

func asString(value interface{}) string {
	switch typed := value.(type) {
	case string:
		return typed
	case fmt.Stringer:
		return typed.String()
	case nil:
		return ""
	default:
		return fmt.Sprintf("%v", typed)
	}
}

func asInt64(value interface{}) (int64, bool) {
	switch typed := value.(type) {
	case int64:
		return typed, true
	case int32:
		return int64(typed), true
	case int:
		return int64(typed), true
	case uint64:
		if typed > uint64(math.MaxInt64) {
			return 0, false
		}
		return int64(typed), true
	case uint32:
		return int64(typed), true
	case float64:
		return int64(typed), true
	case float32:
		return int64(typed), true
	default:
		return 0, false
	}
}

func asBytes(value interface{}) ([]byte, bool) {
	switch typed := value.(type) {
	case []byte:
		return typed, true
	case string:
		return []byte(typed), true
	default:
		return nil, false
	}
}

func splitName(name string) (string, string) {
	parts := strings.Fields(strings.TrimSpace(name))
	if len(parts) == 0 {
		return "", ""
	}
	if len(parts) == 1 {
		return parts[0], ""
	}
	return parts[0], strings.Join(parts[1:], " ")
}

func normalizeError(err error) error {
	switch {
	case errors.Is(err, appstore.ErrAuthCodeRequired):
		return errors.New(authCodeRequiredError)
	case errors.Is(err, appstore.ErrPasswordTokenExpired):
		return errors.New("password token is expired")
	case errors.Is(err, appstore.ErrLicenseRequired):
		return errors.New("License required")
	case errors.Is(err, appstore.ErrTemporarilyUnavailable):
		return errors.New("item is temporarily unavailable")
	case errors.Is(err, appstore.ErrSubscriptionRequired):
		return errors.New("subscription required")
	default:
		return err
	}
}

func decodeRequest(input *C.char, out interface{}) error {
	if input == nil {
		return errors.New("request body is empty")
	}
	payload := C.GoString(input)
	if strings.TrimSpace(payload) == "" {
		return errors.New("request body is empty")
	}
	if err := json.Unmarshal([]byte(payload), out); err != nil {
		return fmt.Errorf("failed to decode request payload: %w", err)
	}
	return nil
}

func respondSuccess(result interface{}) *C.char {
	payload, err := json.Marshal(envelope{OK: true, Result: result})
	if err != nil {
		return respondError(fmt.Errorf("failed to encode response: %w", err))
	}
	return C.CString(string(payload))
}

func respondError(err error) *C.char {
	message := "unknown error"
	if err != nil {
		message = err.Error()
	}
	payload, marshalErr := json.Marshal(envelope{OK: false, Error: message})
	if marshalErr != nil {
		payload = []byte(`{"ok":false,"error":"failed to encode error response"}`)
	}
	return C.CString(string(payload))
}

type fixedMachine struct {
	guid string
}

var _ machine.Machine = fixedMachine{}

func (m fixedMachine) MacAddress() (string, error) {
	if strings.TrimSpace(m.guid) == "" {
		return "", errors.New("device identifier is empty")
	}
	return m.guid, nil
}

func (fixedMachine) HomeDirectory() string {
	return os.TempDir()
}

func (fixedMachine) ReadPassword(fd int) ([]byte, error) {
	_ = fd
	return nil, errors.New("read password is unsupported")
}

type memoryKeychain struct {
	mu     sync.Mutex
	values map[string][]byte
}

var _ keychain.Keychain = (*memoryKeychain)(nil)

func newMemoryKeychain() *memoryKeychain {
	return &memoryKeychain{values: map[string][]byte{}}
}

func (k *memoryKeychain) Get(key string) ([]byte, error) {
	k.mu.Lock()
	defer k.mu.Unlock()

	value, ok := k.values[key]
	if !ok {
		return nil, errors.New("key not found")
	}
	copied := make([]byte, len(value))
	copy(copied, value)
	return copied, nil
}

func (k *memoryKeychain) Set(key string, data []byte) error {
	k.mu.Lock()
	defer k.mu.Unlock()

	copied := make([]byte, len(data))
	copy(copied, data)
	k.values[key] = copied
	return nil
}

func (k *memoryKeychain) Remove(key string) error {
	k.mu.Lock()
	defer k.mu.Unlock()
	delete(k.values, key)
	return nil
}

type memoryCookieJar struct {
	mu      sync.Mutex
	cookies map[string]*stdhttp.Cookie
}

var _ iphttp.CookieJar = (*memoryCookieJar)(nil)

func newMemoryCookieJar() *memoryCookieJar {
	return &memoryCookieJar{
		cookies: map[string]*stdhttp.Cookie{},
	}
}

func (j *memoryCookieJar) Save() error {
	return nil
}

func (j *memoryCookieJar) SetCookies(target *url.URL, cookies []*stdhttp.Cookie) {
	j.mu.Lock()
	defer j.mu.Unlock()

	host := ""
	if target != nil {
		host = strings.ToLower(target.Hostname())
	}

	for _, cookie := range cookies {
		if cookie == nil || cookie.Name == "" {
			continue
		}

		domain := strings.ToLower(strings.TrimSpace(cookie.Domain))
		if domain == "" {
			domain = host
		}
		if domain == "" {
			continue
		}

		path := cookie.Path
		if strings.TrimSpace(path) == "" {
			path = "/"
		}

		key := cookieKey(domain, path, cookie.Name)
		cloned := *cookie
		cloned.Domain = domain
		cloned.Path = path
		j.cookies[key] = &cloned
	}
}

func (j *memoryCookieJar) Cookies(target *url.URL) []*stdhttp.Cookie {
	j.mu.Lock()
	defer j.mu.Unlock()

	if target == nil {
		return nil
	}

	now := time.Now()
	host := strings.ToLower(target.Hostname())
	path := target.EscapedPath()
	if path == "" {
		path = "/"
	}

	result := make([]*stdhttp.Cookie, 0, len(j.cookies))
	for _, cookie := range j.cookies {
		if cookie == nil {
			continue
		}
		if !cookie.Expires.IsZero() && !cookie.Expires.After(now) {
			continue
		}
		if cookie.Secure && target.Scheme != "https" {
			continue
		}
		if !domainMatches(cookie.Domain, host) {
			continue
		}
		if !pathMatches(cookie.Path, path) {
			continue
		}
		cloned := *cookie
		result = append(result, &cloned)
	}

	sort.Slice(result, func(i, k int) bool {
		if result[i].Name != result[k].Name {
			return result[i].Name < result[k].Name
		}
		if result[i].Domain != result[k].Domain {
			return result[i].Domain < result[k].Domain
		}
		return result[i].Path < result[k].Path
	})

	return result
}

func (j *memoryCookieJar) Import(cookies []swiftCookie) {
	j.mu.Lock()
	defer j.mu.Unlock()

	for _, cookie := range cookies {
		if cookie.Name == "" || cookie.Value == "" {
			continue
		}

		domain := "buy.itunes.apple.com"
		if cookie.Domain != nil && strings.TrimSpace(*cookie.Domain) != "" {
			domain = strings.ToLower(strings.TrimSpace(*cookie.Domain))
		}

		path := cookie.Path
		if strings.TrimSpace(path) == "" {
			path = "/"
		}

		httpCookie := &stdhttp.Cookie{
			Name:     cookie.Name,
			Value:    cookie.Value,
			Path:     path,
			Domain:   domain,
			HttpOnly: cookie.HTTPOnly,
			Secure:   cookie.Secure,
		}
		if cookie.ExpiresAt != nil {
			httpCookie.Expires = time.Unix(int64(*cookie.ExpiresAt), 0)
		}

		j.cookies[cookieKey(domain, path, cookie.Name)] = httpCookie
	}
}

func (j *memoryCookieJar) Export() []swiftCookie {
	j.mu.Lock()
	defer j.mu.Unlock()

	now := time.Now()
	result := make([]swiftCookie, 0, len(j.cookies))

	for _, cookie := range j.cookies {
		if cookie == nil {
			continue
		}
		if !cookie.Expires.IsZero() && !cookie.Expires.After(now) {
			continue
		}

		domain := cookie.Domain
		path := cookie.Path
		exported := swiftCookie{
			Name:     cookie.Name,
			Value:    cookie.Value,
			Path:     path,
			Domain:   &domain,
			HTTPOnly: cookie.HttpOnly,
			Secure:   cookie.Secure,
		}
		if !cookie.Expires.IsZero() {
			expires := float64(cookie.Expires.Unix())
			exported.ExpiresAt = &expires
		}
		result = append(result, exported)
	}

	sort.Slice(result, func(i, k int) bool {
		if result[i].Name != result[k].Name {
			return result[i].Name < result[k].Name
		}
		leftDomain := ""
		rightDomain := ""
		if result[i].Domain != nil {
			leftDomain = *result[i].Domain
		}
		if result[k].Domain != nil {
			rightDomain = *result[k].Domain
		}
		if leftDomain != rightDomain {
			return leftDomain < rightDomain
		}
		return result[i].Path < result[k].Path
	})

	return result
}

func cookieKey(domain, path, name string) string {
	return strings.ToLower(domain) + "|" + path + "|" + name
}

func domainMatches(cookieDomain, requestHost string) bool {
	cookieDomain = strings.TrimPrefix(strings.ToLower(strings.TrimSpace(cookieDomain)), ".")
	requestHost = strings.ToLower(strings.TrimSpace(requestHost))
	if cookieDomain == "" || requestHost == "" {
		return false
	}
	return requestHost == cookieDomain || strings.HasSuffix(requestHost, "."+cookieDomain)
}

func pathMatches(cookiePath, requestPath string) bool {
	if cookiePath == "" || cookiePath == "/" {
		return true
	}
	if requestPath == cookiePath {
		return true
	}
	if !strings.HasPrefix(requestPath, cookiePath) {
		return false
	}
	if strings.HasSuffix(cookiePath, "/") {
		return true
	}
	if len(requestPath) > len(cookiePath) {
		return requestPath[len(cookiePath)] == '/'
	}
	return true
}
