package main

import (
	"crypto/tls"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strconv"
	"time"
)

// 定义过期时间
const ExpireDate = "2025-07-31 23:59:59"

// GetBeijingTimeFromTraceURLs 从trace URL获取北京时间
func GetBeijingTimeFromTraceURLs(urls []string, timeout time.Duration) (*time.Time, error) {
	beijingLocation, _ := time.LoadLocation("Asia/Shanghai")
	pattern := regexp.MustCompile(`ts=(\d+)`)
	
	client := &http.Client{
		Timeout: timeout,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: false},
		},
	}

	for _, url := range urls {
		resp, err := client.Get(url)
		if err != nil {
			continue
		}

		if resp.StatusCode != 200 {
			resp.Body.Close()
			continue
		}

		body, err := io.ReadAll(resp.Body)
		resp.Body.Close()
		if err != nil {
			continue
		}

		match := pattern.FindStringSubmatch(string(body))
		if len(match) < 2 {
			continue
		}

		timestamp, err := strconv.ParseInt(match[1], 10, 64)
		if err != nil {
			continue
		}

		utcTime := time.Unix(timestamp, 0).UTC()
		beijingTime := utcTime.In(beijingLocation)
		return &beijingTime, nil
	}

	return nil, fmt.Errorf("所有时间接口请求失败")
}

// CheckExpiration 检查是否过期
func CheckExpiration(urls []string) error {
	beijingTime, err := GetBeijingTimeFromTraceURLs(urls, 5*time.Second)
	if err != nil {
		return fmt.Errorf("获取时间失败: %v", err)
	}

	beijingLocation, _ := time.LoadLocation("Asia/Shanghai")
	expireTime, err := time.ParseInLocation("2006-01-02 15:04:05", ExpireDate, beijingLocation)
	if err != nil {
		return fmt.Errorf("解析过期时间失败: %v", err)
	}

	if beijingTime.After(expireTime) {
		return fmt.Errorf("当前项目已过期")
	}

	fmt.Printf("当前北京时间: %s，未过期\n", beijingTime.Format("2006-01-02 15:04:05"))
	return nil
}

// 调用方法
func main() {
	urls := []string{
		"https://www.cloudflare.com/cdn-cgi/trace",
		"https://www.visa.cn/cdn-cgi/trace",
	}

	if err := CheckExpiration(urls); err != nil {
		fmt.Printf("错误: %v\n", err)
	}
}
