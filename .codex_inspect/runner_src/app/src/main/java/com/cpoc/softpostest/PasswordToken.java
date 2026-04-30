package com.cpoc.softpostest;

import java.security.MessageDigest;

public class PasswordToken {

    private String userName;

    private String pin;

    public PasswordToken(String userName, String pin) {
        this.userName = userName;
        this.pin = pin;
    }

    public String getPasswordToken() {
        String comp1 = sha256(pin);
        String comp2 = sha256(userName);
        String passToken = xor(comp1,comp2);
        return AesEncryptionMPOS.encrypt("C9DDC0BB57179060D9F2E01BE71D65C71D222A063F4DDA858FDC467B173BD146",passToken);
    }


    public static String xor(String key1, String key2){
        String result = "";
        byte[] arr1 = parseHexStr2Byte(key1);
        byte[] arr2 = parseHexStr2Byte(key2);
        byte[] arr3 = new byte[arr1.length];
        for (int i = 0; i < arr1.length; i++) {
            arr3[i] = (byte) (arr1[i] ^ arr2[i]);
        }
        result = parseByte2HexStr(arr3);
        return result;
    }


    // å��å…­è¿›åˆ¶å­—ç¬¦ä¸²è½¬å­—èŠ‚æ•°ç»„
    public static byte[] parseHexStr2Byte(String hexStr) {
        if (hexStr.length() < 1)
            return null;
        byte[] result = new byte[hexStr.length() / 2];
        for (int i = 0; i < hexStr.length() / 2; i++) {
            int high = Integer.parseInt(hexStr.substring(i * 2, i * 2 + 1), 16);
            int low = Integer.parseInt(hexStr.substring(i * 2 + 1, i * 2 + 2),
                    16);
            result[i] = (byte) (high * 16 + low);
        }


        return result;
    }

    // å­—èŠ‚æ•°ç»„è½¬å��å…­è¿›åˆ¶å­—ç¬¦ä¸²
    public static String parseByte2HexStr(byte buf[]) {
        StringBuffer sb = new StringBuffer();
        for (int i = 0; i < buf.length; i++) {
            String hex = Integer.toHexString(buf[i] & 0xFF);
            if (hex.length() == 1) {
                hex = '0' + hex;
            }
            sb.append(hex.toUpperCase());
        }
        return sb.toString();
    }

    public static String sha256(final String base) {
        try{
            final MessageDigest digest = MessageDigest.getInstance("SHA-256");
            final byte[] hash = digest.digest(base.getBytes("UTF-8"));
            final StringBuilder hexString = new StringBuilder();
            for (int i = 0; i < hash.length; i++) {
                final String hex = Integer.toHexString(0xff & hash[i]);
                if(hex.length() == 1)
                    hexString.append('0');
                hexString.append(hex);
            }
            return hexString.toString();
        } catch(Exception ex){
            throw new RuntimeException(ex);
        }
    }

    public static void main(String[] args) {
        System.out.println(sha256("1234"));
    }
}
