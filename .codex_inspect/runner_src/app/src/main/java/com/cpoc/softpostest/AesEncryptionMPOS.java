package com.cpoc.softpostest;

import java.io.UnsupportedEncodingException;
import java.security.InvalidAlgorithmParameterException;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;

import javax.crypto.BadPaddingException;
import javax.crypto.Cipher;
import javax.crypto.IllegalBlockSizeException;
import javax.crypto.NoSuchPaddingException;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;


public class AesEncryptionMPOS {

	public static String MODE = "AES/CBC/PKCS5Padding";

 
		public static String encrypt(String key, String value){

			try {


				Cipher cipher = Cipher.getInstance(MODE);
				
				SecureRandom rnd = new SecureRandom();
				byte[] iv = new byte[cipher.getBlockSize()];
				rnd.nextBytes(iv);
				
				
				String ivEncrypt = parseByte2HexStr(iv);
				
				System.out.println("ivEncrypt "+ivEncrypt);
				
				
				IvParameterSpec ivParams = new IvParameterSpec(iv);
	 
				SecretKeySpec skeySpec = new SecretKeySpec(parseHexStr2Byte(key), "AES");

				cipher.init(Cipher.ENCRYPT_MODE, skeySpec, ivParams);

				byte[] encrypted = cipher.doFinal(value.getBytes());
				System.out.println("encrypted string: " + parseByte2HexStr(encrypted));

				return parseByte2HexStr(encrypted)+parseByte2HexStr(iv);
			} catch (Exception ex) {

				ex.printStackTrace();
			}
			return "";
		}

		
		
	public static String decrypt(String key, String encrypted) {
		try {
			
			byte[] initialVector = null;
			if(encrypted.length()>32) {
				
				String ivDecrypt = encrypted.substring(encrypted.length()-32);
				
				System.out.println("ivDecrypt "+ivDecrypt);
				
				initialVector = parseHexStr2Byte(encrypted.substring(encrypted.length()-32));
				
				encrypted = encrypted.split(ivDecrypt)[0];
				
			}
		 
			IvParameterSpec iv = new IvParameterSpec(initialVector);

			SecretKeySpec skeySpec = new SecretKeySpec(parseHexStr2Byte(key), "AES");

			Cipher cipher = Cipher.getInstance(MODE);
			cipher.init(Cipher.DECRYPT_MODE, skeySpec,iv);

			if (encrypted != null) {
				byte[] original = cipher.doFinal(parseHexStr2Byte(encrypted));
				
				System.out.println("decrypted string: " + new String(original));

				return new String(original);
			}

		} catch (Exception ex) {

			ex.printStackTrace();
		}

		return null;
	}

 
	public static String getKey() {
		StringBuilder key = new StringBuilder();
		for (int i = 0; i < 64; i++) {
			if (i % 2 == 0)
				key.append("3");
			else
				key.append("0");
		}

		return key.toString();
	}

	public static void main(String[] args)
			throws InvalidKeyException, NoSuchPaddingException, NoSuchAlgorithmException, UnsupportedEncodingException,
			BadPaddingException, IllegalBlockSizeException, InvalidAlgorithmParameterException {
		
		String enc = encrypt("C9DDC0BB57179060D9F2E01BE71D65C71D222A063F4DDA858FDC467B173BD146", "Bar12345Bar12345Bar12345Bar12345");


		System.out.println("Encrypted :"+enc);
	
	
		System.out.println(decrypt("C9DDC0BB57179060D9F2E01BE71D65C71D222A063F4DDA858FDC467B173BD146", enc));

	
	
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

}





